require 'aws/s3'

module AWS

  class Admin < Sinatra::Base

    helpers do
      include ::S3::Helpers
      include ::S3::AdminHelpers
    end

    set :sessions, :on
    enable :inline_templates

    before do
      ActiveRecord::Base.verify_active_connections!
    end

    get '/buckets/?' do
      login_required
      load_buckets
      r :buckets, "Buckets"
    end

    post '/buckets/?' do
      login_required
      begin
        Bucket.find_root(params['bucket']['name'])
        load_buckets
        @bucket.errors.add_to_base("A bucket named `#{params['bucket']['name']}' already exists.")
      rescue ::S3::NoSuchBucket
         bucket = Bucket.new(params['bucket'])
	 redirect '/control/buckets' if bucket.save()
	 load_buckets
	 @bucket.errors.add_to_base("Invalid bucket name.")
      end
      r :buckets, "Buckets"
    end

    get '/buckets/:bucket/?' do
      login_required
      @bucket = Bucket.find_root(params[:bucket])
      only_can_read @bucket
      @files = Slot.find :all, :conditions => ['deleted = 0 AND parent_id = ?', @bucket.id], :include => :torrent, :order => 'name'
      r :files, "/#{@bucket.name}"
    end

    post '/buckets/:bucket/?' do
      login_required
      @bucket = Bucket.find_root(params[:bucket])
      only_can_write @bucket

      if params['upfile'].nil? || params['upfile'].instance_of?(String)
	@files = Slot.find :all, :conditions => ['deleted = 0 AND parent_id = ?', @bucket.id], :order => 'name'
	redirect "/control/buckets/#{params[:bucket]}"
      end

      tmpf = params['upfile'][:tempfile]
      readlen, md5 = 0, Digest::MD5.new
      while part = tmpf.read(::S3::BUFSIZE)
	readlen += part.size
	md5 << part
      end

      fileinfo = FileInfo.new
      fileinfo.mime_type = params['upfile'][:type] || "binary/octet-stream"
      fileinfo.size = readlen
      fileinfo.md5 = md5.hexdigest
      fileinfo.etag = '"' + md5.hexdigest + '"'

      mdata = {}
      if defined?(EXIFR) && fileinfo.mime_type =~ /jpg|jpeg/
	photo_data = EXIFR::JPEG.new(tmpf.path).to_hash
	photo_data.each_pair do |key,value|
	  tmp = key.to_s.gsub(/[^a-z0-9]+/i, '-').downcase.gsub(/-$/,'')
	  mdata[tmp] = value.to_s
	end
      end

      params['fname'] = params['upfile'][:filename] if params['fname'].blank?
      begin
	slot = @bucket.find_slot(params['fname'])
	if slot.versioning_enabled?
	  nslot = slot.clone()
	  slot.update_attributes(:deleted => true)
	  slot = nslot
	end
	fileinfo.path = slot.obj.path
	file_path = File.join(::S3::STORAGE_PATH,fileinfo.path)
	slot.update_attributes(:owner_id => @user.id, :meta => mdata, :obj => fileinfo, :size => fileinfo.size)
	FileUtils.mv(tmpf.path, file_path,{ :force => true })
      rescue ::S3::NoSuchKey
	fileinfo.path = File.join(params[:bucket], rand(10000).to_s(36) + '_' + File.basename(tmpf.path))
	fileinfo.path.succ! while File.exists?(File.join(::S3::STORAGE_PATH, fileinfo.path))
	file_path = File.join(::S3::STORAGE_PATH,fileinfo.path)
	FileUtils.mkdir_p(File.dirname(file_path))
	FileUtils.mv(tmpf.path, file_path)
	slot = Slot.create(:name => params['fname'], :owner_id => @user.id, :meta => mdata, :obj => fileinfo, :size => fileinfo.size)
	slot.grant(:access => params['facl'].to_i)
	@bucket.add_child(slot)
      end

      if slot.versioning_enabled?
	begin
	  slot.git_repository.add(File.basename(fileinfo.path))
	  slot.git_repository.commit("Added #{slot.name} to the Git repository.")
	  slot.git_update
	  slot.update_attributes(:version => slot.git_object.objectish)
	rescue => err
	  puts "[#{Time.now}] GIT: #{err}"
	end
      end

      redirect "/control/buckets/#{params[:bucket]}"
    end

    post '/buckets/:bucket/versioning/?' do
      login_required
      @bucket = Bucket.find_root(params[:bucket])
      only_can_write @bucket
      @bucket.git_init if defined?(Git)
      redirect "/control/buckets/#{@bucket.name}"
    end

    get %r{^/changes/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root params[:captures].first
      @file = @bucket.find_slot(params[:captures].last)
      only_owner_of @bucket
      @versions = @bucket.git_repository.log.path(File.basename(@file.obj.path))
      r :changes, "Commit Log", :popup
    end

    post '/delete/:bucket/?' do
      login_required
      @bucket = Bucket.find_root(params[:bucket])
      only_owner_of @bucket
      if Slot.count(:conditions => ['deleted = 0 AND parent_id = ?', @bucket.id]) > 0
	# FIXME: error message, bucket is not empty
      else
	@bucket.remove_from_filesystem()
	@bucket.destroy()
      end
      redirect "/control/buckets"
    end

    post %r{^/delete/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      only_can_write @bucket
      @slot = @bucket.find_slot(params[:captures].last)

      if @slot.versioning_enabled?
	@slot.git_repository.remove(File.basename(@slot.obj.path))
	@slot.git_repository.commit("Removed #{@slot.name} from the Git repository.")
	@slot.git_update
      end

      @slot.remove_from_filesystem()
      @slot.destroy()
      redirect "/control/buckets/#{params[:captures].first}"
    end

    get %r{^/acl/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      only_can_write_acp @bucket
      @slot = @bucket.find_slot(params[:captures].last)
      only_can_write @slot
      r :acl, "Modify File Access", :popup
    end

    post %r{^/acl/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      @slot = @bucket.find_slot(params[:captures].last)
      only_owner_of @slot
      case params[:acl]['type']
      when "email"
	@user = AWSAuth::User.find(:first, :conditions => [ 'key = ? OR email = ?', params[:acl]['user_id'], params[:acl]['user_id'] ])
	update_user_access(@slot,@user,"#{Bit.acl_text.invert[params[:acl]['access']]}00".to_i(8)) if @user
      when "http://acs.amazonaws.com/groups/global/AuthenticatedUsers"
	@slot.access &= ~(@slot.access.to_s(8)[1,1].to_i*10)
	@slot.access |= (Bit.acl_text.invert[params[:acl]['access']]*10).to_s.to_i(8)
      when "http://acs.amazonaws.com/groups/global/AllUsers"
	@slot.access &= ~@slot.access.to_s(8)[2,1].to_i
	@slot.access |= Bit.acl_text.invert[params[:acl]['access']].to_s.to_i(8)
      end
      @slot.save()
      redirect "/control/acl/#{@bucket.name}/#{@slot.name}"
    end

    get %r{^/meta/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      @slot = @bucket.find_slot(params[:captures].last)
      only_can_write @slot
      r :meta, "Metadata", :popup
    end

    post %r{^/meta/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      @slot = @bucket.find_slot(params[:captures].last)
      only_can_write @slot

      newm = {}
      params[:m].each do |k,v|
	newm[k] = v unless v.blank?
      end
      if !params[:meta]['key'].blank? && !params[:meta]['value'].blank?
	if params[:meta]['key'] =~ /^[A-Za-z0-9\-]+$/
	  newm[params[:meta]['key']] = params[:meta]['value']
	else
	  @slot.errors.add(:key, "can only contain letters, numbers and dashes")
	end
      end

      @slot.update_attributes({ :meta => newm })
      r :meta, "Metadata", :popup
    end

  end

end

AWS::Admin.add_tab('buckets','/control/buckets')

__END__


@@ popup
%html
  %head
    %title #{@title}
    %style{ :type => "text/css" } 
      @import '/control/s/css/control.css';
    %script{ :language => 'javascript', :src => '/control/s/js/prototype.js' }
  %body
    %div#content
      = yield

@@ buckets
- if @buckets.any?
  %table
    %thead
      %tr
        %th Name
        %th Contains
        %th Updated on
        %th Info
        %th Actions
    %tbody
      - @buckets.each do |bucket|
        %tr
          %th
            %a{ :href => "/control/buckets/#{bucket.name}" } #{bucket.name}
          %td #{bucket.total_children rescue 0} files
          %td #{bucket.updated_at}
          %td #{bucket.access_readable + (bucket.versioning_enabled? ? ",versioned" : "")}
          %td
            %a{ :href => "/control/delete/#{bucket.name}", :onClick => S3::POST, :title => "Delete Bucket #{bucket.name}" } Delete
- else
  %p A sad day. You have no buckets yet.
%h3 Create a Bucket
%form.create{ :method => "post" }
  = preserve errors_for(@bucket)
  %input{ :name => "bucket[owner_id]", :type => "hidden", :value => @bucket.owner_id }
  %div.required
    %label{ :for => "bucket[name]" } Bucket Name
    %input{ :name => "bucket[name]", :type => "text", :value => @bucket.name }
  %div.required
    %label{ :for => "bucket[access]" } Permissions
    %select{ :name => "bucket[access]" }
      - S3::CANNED_ACLS.sort.each do |acl,perm|
        - opts = { :value => perm }
        - opts[:selected] = true if perm == @bucket.access
        %option{ opts } #{acl}
  %input#newbucket{ :type => "submit", :value => "Create", :name => "newbucket" }

@@ files
%p Click on a file name to get file details.
%table
  %caption
    - if defined?(Git)
      %span{ :style => "float:right" }
        - if !@bucket.versioning_enabled?
          %a{ :href => "/control/buckets/#{@bucket.name}/versioning", :onClick => S3::POST } Enable Versioning For This Bucket
        - else
          Versioning Enabled
    %a{ :href => "/control/buckets" } &larr; Buckets
  %thead
    %tr
      %th File
      %th Size
      %th Permission
  %tbody
    - if @files.empty?
      %tr
        %td{ :colspan => "3", :style => "padding:15px;text-align:center" } No Files
    - @files.each do |file|
      %tr
        %td
          %a{ :href => "javascript:///", :onclick => "$('details-#{file.id}').toggle()" } #{file.name}
          %div.details{ :id => "details-#{file.id}", :style => "display:none" }
            - if @bucket.versioning_enabled?
              %p Revision: #{file.version}
            - if file.torrent
              %p #{file.torrent.seeders} seeders &bull; #{file.torrent.leechers} leechers &bull; #{file.torrent.total} downloads
            %p Last modified on #{file.updated_at}
            %p
              %a{ :href => signed_url("/#{@bucket.name}/#{file.name}"), :target => "_blank" } Get
              &bull;
              %a{ :href => "/control/acl/#{@bucket.name}/#{file.name}", :onclick => S3::POPUP } Access
              &bull;
              %a{ :href => "/control/meta/#{@bucket.name}/#{file.name}", :onclick => S3::POPUP } Meta
              &bull;
              - if @bucket.versioning_enabled?
                %a{ :href => "/control/changes/#{@bucket.name}/#{file.name}", :onclick => S3::POPUP } Changes
                &bull;
              - if defined?(RubyTorrent)
                %a{ :href => signed_url("/#{@bucket.name}/#{file.name}") + "&torrent", :target => "_blank" } Torrent
                &bull;
              %a{ :href => "/control/delete/#{@bucket.name}/#{file.name}", :onclick => S3::POST, :title => "Delete file #{file.name}" } Delete
        %td #{number_to_human_size(file.size)}
        %td #{file.access_readable}
%div#results
%div#progress-bar{ :style => "display:none" }
%iframe#upload{ :name => "upload", :style => "display:none" }
- @upid = Time.now.to_f
- form_options = { :action => "?upload_id=#{@upid}", :id => "upload-form", :method => 'post', :enctype => 'multipart/form-data' }
- form_options.merge!({ :onsubmit => "UploadProgress.monitor('#{@upid}')", :target => "upload" }) if $UPLOAD_PROGRESS
%form.create{ form_options }
  %h3 Upload a File
  %div.required
    %input{ :name => "upfile", :type => "file" }
  %div.optional
    %label{ :for => "fname"} File Name
    %input{ :name => "fname", :type => "text" }
  %div.required
    %label{ :for => "facl" } Permissions
    %select{ :name => "facl" }
      - S3::CANNED_ACLS.sort.each do |acl, perm|
        - opts = { :value => perm }
        - opts[:selected] = true if perm == @bucket.access
        %option{ opts } #{acl}
  %input#newfile{ :name => "newfile", :value => "Create", :type => "submit" }

@@ meta
%form.create{ :method => "post", :style => "text-align:left" }
  = preserve errors_for(@slot)
  %table
    %thead
      %tr
        %th Key
        %th Value
    %tbody
      - if @slot.meta.empty?
        %tr
          %td{ :colspan => "2", :style => "padding:8px;text-align:center" } No Metadata for #{@slot.name}
      - else
        - @slot.meta.each do |k,v|
          %tr
            %td #{k}
            %td
              %input{ :name => "m[#{k}]", :type => "text", :value => v, :style => "width:100%" }
    %thead
      %tr
        %th{ :colspan => "2" } New Key
    %tbody
      %tr
        %td
          %input{ :name => "meta[key]", :type => "text", :style => "width:100%" }
        %td
          %input{ :name => "meta[value]", :type => "text", :style => "width:100%" }
  %div{ :style => "text-align:center;margin-top:15px" }
    %input{ :type => "submit", :value => "Update" }

@@ changes
%table
  %thead
    %tr
      %th Commit Log For #{@file.name}
  %tbody
    - @versions.each do |version|
      %tr
        %td
          %div
            %a{ :target => "_blank", :href => signed_url("/#{@bucket.name}/#{@file.name}") + "&version-id=#{version.sha}" } #{version.sha}
          %div On: #{version.date}
          %div By: #{version.author.name} <#{version.author.email}>

@@ acl
%table
  %thead
    %tr
      %th For
      %th Access
  %tbody
    - @slot.acl_list.each_pair do |key,acl|
      %tr
        %td #{acl[:type] == "CanonicalUser" ? "#{acl[:id]} (#{acl[:name]})" : acl[:uri].split("/").last}
        %td #{acl[:access]}
%div{ :style => "text-align:left;margin-top:10px" }
  %h3 Modify File Access
  %form.create{ :method => "post" }
    %div.required
      %label{ :for => "acl_type" } For
      %select#acl_type{ :name => "acl[type]", :onchange => "$('user_id_box').style.display = this.value == 'email' ? 'block' : 'none';" }
        %option{ :value => "http://acs.amazonaws.com/groups/global/AllUsers" } AllUsers
        %option{ :value => "http://acs.amazonaws.com/groups/global/AuthenticatedUsers" } AuthenticatedUsers
        %option{ :value => "email" } By ID/Email
    %div#user_id_box.required{ :style => "display:none" }
      %label{ :for => "user_id" } User ID/Email
      %input#user_id{ :type => "text", :name => "acl[user_id]" }
    %div.required
      %label{ :for => "user_access" } Access
      %select#user_access{ :name => "acl[access]" }
        %option{ :value => "READ" } READ
        %option{ :value => "READ_ACP" } READ_ACP
        %option{ :value => "WRITE" } WRITE
        %option{ :value => "WRITE_ACP" } WRITE_ACP
    %input{ :type => "submit", :value => "Update" }
