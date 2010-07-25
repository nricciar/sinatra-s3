$:.unshift "./lib"
require 's3'
require 'wikicloth'

# Initial setup
begin
  Bucket.find_root('wiki')
rescue S3::NoSuchBucket
  wiki_owner = User.find_by_login('wiki')
  if wiki_owner.nil?
     class S3KeyGen
       include S3::Helpers
       def secret() generate_secret(); end;
       def key() generate_key(); end;
      end
      puts "** No wiki user found, creating the `wiki' user."
      wiki_owner = User.create :login => "wiki", :password => DEFAULT_PASSWORD,
        :email => "wiki@parkplace.net", :key => S3KeyGen.new.key(), :secret => S3KeyGen.new.secret(),
        :activated_at => Time.now
  end
  bucket = Bucket.create(:name => 'wiki', :owner_id => wiki_owner.id, :access => 438)
  if defined?(Git)
    bucket.git_init
  else
    puts "Git support not found therefore Wiki history is disabled."
  end
end

# template and link handling
class CustomLinkHandler < WikiCloth::WikiLinkHandler

  def url_for(page)
    page = page.strip.gsub(/\s+/,'_')
    page = "/#{$1.downcase}/#{$2}" if page =~ /^([A-Za-z]+):(.*)$/
    page
  end

  def link_attributes_for(page)
     { :href => url_for(page) }
  end

  def include_resource(resource,options=[])
    if params[resource].nil?
      begin
        bucket = Bucket.find_root('templates')
        slot = bucket.find_slot(resource)
        unless slot.nil?
          file = open(File.join(STORAGE_PATH, slot.obj.path))
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

class Wiki

  SITE_NAME = "Wiki on Sinatra-S3"
  
  def initialize(app)
    @app = app
    @headers = {}
    @status = 200
    @req = nil
  end

  def default_layout(title)
    html = Builder::XmlMarkup.new
    html.html do
      html.head do
        html.title title
        html.style "@import '/control/s/css/control.css';", :type => 'text/css'
        html.style ".editsection { display:none }", :type => "text/css"
      end
      html.body do
        html.div :style => "text-align:left;padding:10px 0;width:700px;margin:0 auto" do
          html.h1 { html.a SITE_NAME, :href => "/" }
        end
        html.div :id => "page" do
          if @status <= 300
            html.div :class => "menu" do
              html.ul do
                rp = @req.params
                html.li { html.a "Content", :href => @req.env['REQUEST_PATH'], :class => (!rp.has_key?('edit') && !rp.has_key?('history') ? "active" : "") }
                html.li { html.a "Edit", :href => "#{@req.env['REQUEST_PATH']}?edit", :class => (rp.has_key?('edit') ? "active" : "") }
                html.li { html.a "History", :href => "#{@req.env['REQUEST_PATH']}?history", :class => (rp.has_key?('history') ? "active" : "") } if defined?(Git)
              end
            end
          end
          html.h1 @req.env['REQUEST_PATH'] =~ /\/([^\/]+)$/ ? "#{$1.gsub('_',' ')}" : "Sinatra-S3 Wiki"
          yield html
        end
      end
    end
    @status = 200
    @headers['Content-Type'] = 'text/html'
    @headers['Content-Length'] = html.target!.length.to_s
    html.target!
  end

  def call(env)
    @req = Rack::Request.new(env)
    return @app.call(env) if @req.env['HTTP_AUTHORIZATION']

    if @req.params.has_key?('edit') || @req.params.has_key?('history')
      env['HTTP_IF_MODIFIED_SINCE'] = nil
      env['HTTP_IF_NONE_MATCH'] = nil
    end
    @status, @headers, @body = @app.call(env)

    if @req.params.has_key?('edit')
      @body = @body.instance_of?(File) ? @body.read : @body.to_s
      @body = default_layout("Edit Page") do |html|
        html.h2 "Edit Page"
        html.form :class => "create", :action => env['REQUEST_PATH'], :method => "POST" do
          html.input :type => "hidden", :name => "redirect", :value => env['REQUEST_PATH']
          html.input :type => "hidden", :name => "Content-Type", :value => "text/wiki"
          html.div :class => "required" do
             page_contents = @status >= 300 ? "" : @body
             html.label "Contents", :for => "page_contents"
             html.textarea page_contents, :name => "file", :id => "page_contents", :style => "width:100%;height:20em"
          end
          html.div :class => "required" do
             html.label "Comment:", :for => "page_comment"
             html.input :type => "text", :name => "x-amz-meta-comment", :id => "page_comment"
          end
          html.input :type => "submit", :value => "Update"
        end
      end
    elsif @req.params.has_key?('history')
      @body = default_layout("Page History") do |html|
        html.h2 "Edit History"
        if env['REQUEST_PATH'] =~ /^\/(.+?)\/(.+)$/
          @bucket = Bucket.find_root($1)
          @revisions = Slot.find(:all, :conditions => [ 'name = ?', $2 ], :order => "id DESC")
          html.ul do
            @revisions.each do |rev|
              html.li do
                html.p do 
                  html.a rev.meta['comment'], :href => "#{env['REQUEST_PATH']}?version-id=#{rev.version}"
                  html << " on #{rev.updated_at}"
                end
              end
            end
          end
        end
      end
    else
      if @headers['Content-Type'] =~ /xml/ && @status >= 300
        @body = @body.instance_of?(File) ? @body.read : @body.to_s
        case
        when @body =~ /NoSuchBucket/ # invalid namespace
          @body = default_layout("Invalid Namespace") do |html|
            html.h2 "Invalid Namespace" 
            html.p "The namespace you requested does not exist."
          end
        when @body =~ /NoSuchKey/ # new (non-existant) wiki page
          @body = default_layout("Page Not Found") do |html|
            html.h2 "Page Does Not Exist"
            html.p { html << "The page you were trying to access does not exist.  Perhaps you would like to <a href=\"#{env['REQUEST_PATH']}?edit\">create it</a>?" }
          end
        when @body =~ /AccessDenied/
          @body = default_layout("Access Denied") do |html|
            html.h2 "Access Denied"
            html.p "You do not have permission to access this page."
          end
        end
      end
    end

    if @headers['Content-Type'] =~ /wiki/
      p = {}
      @headers.each { |k,v| p[$1.upcase.gsub(/\-/,'_')] = v if k =~ /x-amz-(.*)/ }

      wiki_page = WikiCloth::WikiCloth.new({
        :data => @body.instance_of?(File) ? @body.read : @body.to_s,
        :link_handler => CustomLinkHandler.new,
        :params => p
      })

      @body = default_layout("") do |html|
        html << wiki_page.to_html
      end
    end

    if env['REQUEST_PATH'].blank? || env['REQUEST_PATH'] == '/'
      @status = 301
      @headers['Location'] = '/wiki/Main_Page'
    end

    [@status.nil? ? 200 : @status,@headers,@body]
  end

end

use Wiki
use S3::Admin
run S3::Application
