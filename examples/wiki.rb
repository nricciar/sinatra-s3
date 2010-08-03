require 'sinatra-s3'
require 'wikicloth'

S3::Application.callback :mime_type => 'text/wiki' do
  headers["Content-Type"] = "text/html"
  if params.has_key?('edit')
    r :edit, "Editing #{@slot.name.gsub(/_/,' ')}"
  elsif params.has_key?('diff')
    @diff = Bit.diff(params[:diff],params[:to])
    r :diff, "Changes to #{@slot.name.gsub(/_/,' ')}"
  elsif params.has_key?('history')
    @history = Slot.find(:all, :conditions => [ 'name = ? AND parent_id = ?', @slot.name, @slot.parent_id ], :order => "id DESC", :limit => 20)
    r :history, "Revision history for #{@slot.name.gsub(/_/,' ')}"
  else
    p = {}
    headers.each { |k,v| p[$1.upcase.gsub(/\-/,'_')] = v if k =~ /x-amz-(.*)/ }
    @wiki = WikiCloth::WikiCloth.new({
      :data => response.body.respond_to?(:read) ? response.body.read : response.body.to_s,
      :link_handler => CustomLinkHandler.new,
      :params => p
    })
    r :wiki, @slot.name.gsub(/_/,' ')
  end
end

S3::Application.callback :error => 'NoSuchKey' do
  headers["Content-Type"] = "text/html"
  if params.has_key?('edit')
    r :edit, "Edit Page"
  else
    r :does_not_exist, "Page Does Not Exist"
  end
end

S3::Application.callback :error => 'AccessDenied' do
  if env['PATH_INFO'].nil? || env['PATH_INFO'] == '/'
    redirect '/wiki/Main_Page'
  else
    status 401
    headers["WWW-Authenticate"] = %(Basic realm="wiki")
    headers["Content-Type"] = "text/html"
    r :access_denied, "Access Denied"
  end
end

S3::Application.callback :when => 'before' do
  #fix some caching issues
  if params.any? { |k,v| ["edit","history","diff"].include?(k) }
    env.delete('HTTP_IF_MODIFIED_SINCE')
    env.delete('HTTP_IF_NONE_MATCH')
  end

  auth = Rack::Auth::Basic::Request.new(env)
  next unless auth.provided? && auth.basic?

  user = User.find_by_login(auth.credentials[0])
  next if user.nil?

  # Convert a valid basic authorization into a proper S3 AWS
  # Authorization header
  if user.password == hmac_sha1( auth.credentials[1], user.secret )
    uri = env['PATH_INFO']
    uri += "?" + env['QUERY_STRING'] if S3::RESOURCE_TYPES.include?(env['QUERY_STRING'])
    canonical = [env['REQUEST_METHOD'], env['HTTP_CONTENT_MD5'], env['CONTENT_TYPE'],
      (env['HTTP_X_AMZ_DATE'] || env['HTTP_DATE']), uri]
    env['HTTP_AUTHORIZATION'] = "AWS #{user.key}:" + hmac_sha1(user.secret, canonical.map{|v|v.to_s.strip} * "\n")
  end
end

class CustomLinkHandler < WikiCloth::WikiLinkHandler
  def url_for(page)
    page = page.strip.gsub(/\s+/,'_')
    page = "/#{$1.downcase}/#{$2}" if page =~ /^([A-Za-z]+):(.*)$/
    page
  end

  def link_attributes_for(page)
     { :href => url_for(page) }
  end

  def external_link(url,text)
    self.external_links << url
    elem.a({ :href => url, :target => "_blank", :class => "exlink" }) { |x| x << (text.blank? ? url : text) }
  end

  def include_resource(resource,options=[])
    if params[resource].nil?
      begin
        bucket = Bucket.find_root('templates')
        slot = bucket.find_slot(resource)
        unless slot.nil?
          file = open(File.join(S3::STORAGE_PATH, slot.obj.path))
          wiki_page = WikiCloth::WikiCloth.new({
            :data => file.instance_of?(File) ? file.read : file.to_s,
            :link_handler => self,
            :params => params
          })
          return wiki_page.to_html
        end
      rescue S3::NoSuchKey
        puts "Unknown resource #{resource}"
      end
    else
      return params[resource]
    end
  end
end

class S3::Application < Sinatra::Base; enable :inline_templates; end

__END__

@@ layout
%html
  %head
    %title #{@title}
    %style{:type => "text/css"} @import '/control/s/css/control.css';
    %style{:type => "text/css"} @import '/control/s/css/wiki.css';
    %script{ :type => "text/javascript", :language => "JavaScript", :src => "/control/s/js/prototype.js" }
    %script{ :type => "text/javascript", :language => "JavaScript", :src => "/control/s/js/wiki.js" }
  %body
    %div#header
      %h1
        %a{:href => "/"} Wiki on Sinatra-S3
    %div#page
      - if status < 300
        %div.menu
          %ul
            %li
              %a{ :href => "#{env['PATH_INFO']}", :class => (!params.any? { |k,v| ["diff","history","edit"].include?(k) } ? "active" : "") } Content
            %li
              %a{ :href => "#{env['PATH_INFO']}?edit", :class => (params.has_key?('edit') ? "active" : "") } Edit
            - if defined?(Git)
              %li
                %a{ :href => "#{env['PATH_INFO']}?history", :class => (params.any? { |k,v| ["diff","history"].include?(k) } ? "active" : "") } History
      %h1 #{env['PATH_INFO'] =~ /\/([^\/]+)$/ ? "#{$1.gsub('_',' ')}" : "Sinatra-S3 Wiki"}
      = yield

@@ access_denied
%h2 Access Denied
%p You are not authorized to access the specified resource.

@@ diff
%div#content
  %p Change Summary: #{@diff.stats[:total][:insertions]} insertions and #{@diff.stats[:total][:deletions]} deletions
  - @lines = @diff.patch.gsub('<','&lt;').gsub('>','&gt;').split("\n")
  - @lines[4..-1].each do |line|
    - case
    - when line =~ /\-([0-9]+)(,([0-9]+)|) \+([0-9]+),([0-9]+)/
      %div{ :style => "font-weight:bold;padding:5px 0" } Line #{$1}
    - when line[0,1] == "\\"
    - when line[0,1] == "+"
      %ins{ :style => "background-color:#99ff99" } &nbsp;#{line[1,line.length]}
    - when line[0,1] == "-"
      %del{ :style => "background-color:#ff9999" } &nbsp;#{line[1,line.length]}
    - else
      %div{ :style => "background-color:#ebebeb" } &nbsp;#{line}

@@ does_not_exist
%h2 Page Does Not Exist
%p
  The page you were trying to access does not exist.  Perhaps you would like to
  %a{ :href => "#{env['PATH_INFO']}?edit" } create it
  ?

@@ edit
%h2 #{@slot.nil? ? "Edit Page" : "Editing #{@slot.name.gsub(/_/,' ')}"}
%form#edit_page_form.create{ :method => "POST", :action => env['PATH_INFO'] }
  %input{ :type => "hidden", :name => "redirect", :value => env['PATH_INFO'] }
  %input{ :type => "hidden", :name => "Content-Type", :value => "text/wiki" }
  %div.required
    - page_contents = status >= 300 ? "" : (response.body.respond_to?(:read) ? response.body.read : response.body.to_s)
    %label{ :for => "page_contents" } Contents
    %textarea{ :name => "file", :id => "page_contents", :style => "width:100%;height:20em" } #{page_contents}
  %div.required
    %label{ :for => "page_comment" } Comment:
    %input{ :type => "text", :name => "x-amz-meta-comment", :id => "page_comment" }
  %input{ :type => "submit", :value => "Update" }

@@ history
%h2 Revision history of #{@slot.name.gsub(/_/,' ')}
%form{ :action => env['PATH_INFO'], :method => "GET" }
  %table#revision_history
    - @history.each_with_index do |rev, count|
      %tr
        - if @history.length > 1
          %td.check
            %input.from{ :type => "radio", :name => "diff", :value => rev.version, :checked => (count == 1 ? true : false), :style => (count > 0 ? nil : "display:none") }
          %td.check
            %input.to{ :type => "radio", :name => "to", :value => rev.version, :checked => (count == 0 ? true : false) }
        %td
          %a{ :href => "#{env['PATH_INFO']}?version-id=#{rev.version}" } #{rev.meta['comment']}
          on #{rev.updated_at}
  - if @history.length > 1
    %input{ :type => "submit", :value => "Compare Revisions" }

@@ wiki
%div#wiki_page
  = preserve @wiki.to_html
