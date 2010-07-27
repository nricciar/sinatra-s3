require 'aws/s3'

module S3

  class Admin < Sinatra::Base

    helpers do
      include S3::Helpers
      include S3::AdminHelpers
    end

    set :sessions, :on

    before do
      ActiveRecord::Base.verify_active_connections!
    end

    get '/control/?' do
      login_required
      redirect '/control/buckets'
    end

    get %r{^/control/s/(.*)} do
      open(File.join(PUBLIC_PATH, params[:captures].first))
    end

    get '/control/login' do
      login_view
    end

    post '/control/login' do
      @user = User.find_by_login params[:login]
      if @user
	if @user.password == hmac_sha1( params[:password], @user.secret )
	  session[:user_id] = @user.id
	  redirect '/control/buckets'
	else
	  @user.errors.add(:password, 'is incorrect')
	end
      else
	@user = User.new
	@user.errors.add(:login, 'not found')
      end
      login_view
    end

    get '/control/logout' do
      session[:user_id] = nil
      redirect '/control'
    end

    get '/control/buckets/?' do
      login_required
      load_buckets
      bucket_view
    end

    post '/control/buckets/?' do
      login_required
      begin
        Bucket.find_root(params['bucket']['name'])
        load_buckets
        @bucket.errors.add_to_base("A bucket named `#{@input['bucket']['name']}' already exists.")
      rescue NoSuchBucket
         bucket = Bucket.new(params['bucket'])
	 redirect '/control/buckets' if bucket.save()
	 load_buckets
	 @bucket.errors.add_to_base("Invalid bucket name.")
      end
      bucket_view
    end

    get '/control/buckets/:bucket/?' do
      login_required
      @bucket = Bucket.find_root(params[:bucket])
      only_can_read @bucket
      @files = Slot.find :all, :conditions => ['deleted = 0 AND parent_id = ?', @bucket.id], :order => 'name'
      files_view
    end

    post '/control/buckets/:bucket/?' do
      login_required
      @bucket = Bucket.find_root(params[:bucket])
      only_can_write @bucket

      if params['upfile'].nil? || params['upfile'].instance_of?(String)
	@files = Slot.find :all, :conditions => ['deleted = 0 AND parent_id = ?', @bucket.id], :order => 'name'
	redirect "/control/buckets/#{params[:bucket]}"
      end

      tmpf = params['upfile'][:tempfile]
      readlen, md5 = 0, MD5.new
      while part = tmpf.read(BUFSIZE)
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
	file_path = File.join(STORAGE_PATH,fileinfo.path)
	slot.update_attributes(:owner_id => @user.id, :meta => mdata, :obj => fileinfo, :size => fileinfo.size)
	FileUtils.mv(tmpf.path, file_path,{ :force => true })
      rescue NoSuchKey
	fileinfo.path = File.join(params[:bucket], rand(10000).to_s(36) + '_' + File.basename(tmpf.path))
	fileinfo.path.succ! while File.exists?(File.join(STORAGE_PATH, fileinfo.path))
	file_path = File.join(STORAGE_PATH,fileinfo.path)
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

    post '/control/buckets/:bucket/versioning/?' do
      login_required
      @bucket = Bucket.find_root(params[:bucket])
      only_can_write @bucket
      @bucket.git_init if defined?(Git)
      redirect "/control/buckets/#{@bucket.name}"
    end

    get %r{^/control/changes/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root params[:captures].first
      @file = @bucket.find_slot(params[:captures].last)
      only_owner_of @bucket
      @versions = @bucket.git_repository.log.path(File.basename(@file.obj.path))
      changes_view
    end

    post '/control/delete/:bucket/?' do
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

    post %r{^/control/delete/(.+?)/(.+)$} do
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

    get "/control/profile/?" do
      login_required
      @usero = @user
      profile_view
    end

    post "/control/profile/?" do
      login_required
      @user.update_attributes(params['user'])
      @usero = @user
      profile_view
    end

    get "/control/users/?" do
      login_required
      only_superusers
      @usero = User.new
      @users = User.find :all, :conditions => ['deleted != 1'], :order => 'login'
      users_view
    end

    post "/control/users/?" do
      login_required
      only_superusers
      @usero = User.new params['user'].merge(:activated_at => Time.now)
      if @usero.valid?
	@usero.save()
	redirect "/control/users"
      else
	@users = User.find :all, :conditions => ['deleted != 1'], :order => 'login'
	users_view
      end
    end

    get "/control/users/:login/?" do
      login_required
      only_superusers
      @usero = User.find_by_login params[:login]
      profile_view
    end

    post "/control/users/:login/?" do
      login_required
      only_superusers
      @usero = User.find_by_login params[:login]

      # if were not changing passwords remove blank values
      if params['user']['password'].blank? && params['user']['password_confirmation'].blank?
	params['user'].delete('password')
	params['user'].delete('password_confirmation')
      end

      if @usero.update_attributes(params['user'])
        redirect "/control/users/#{@usero.login}"
      else
	profile_view
      end
    end

    post "/control/users/delete/:login/?" do
      login_required
      only_superusers
      @usero = User.find_by_login params[:login]
      if @usero.id == @user.id
	# FIXME: notify user they cannot delete themselves
      else
	@usero.destroy
      end
      redirect "/control/users"
    end

    get %r{^/control/edit/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      @slot = @bucket.find_slot(params[:captures].last)
      only_can_write @slot
      edit_view
    end

    get %r{^/control/acl/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      only_can_write_acp @bucket
      @slot = @bucket.find_slot(params[:captures].last)
      only_can_write @slot
      acl_view
    end

    post %r{^/control/acl/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      @slot = @bucket.find_slot(params[:captures].last)
      only_owner_of @slot
      case params[:acl]['type']
      when "email"
	@user = User.find(:first, :conditions => [ 'key = ? OR email = ?', params[:acl]['user_id'], params[:acl]['user_id'] ])
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

    get %r{^/control/meta/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      @slot = @bucket.find_slot(params[:captures].last)
      only_can_write @slot
      meta_view
    end

    post %r{^/control/meta/(.+?)/(.+)$} do
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
      meta_view
    end

    protected
    def default_layout(str)
      builder do |html|
	html.html do
	  html.head do
	    html << "<title>Control Center &raquo; #{str}</title>"
	    html.script " ", :language => 'javascript', :src => '/control/s/js/prototype.js' 
	    html.script " ", :language => 'javascript', :src => '/control/s/js/upload_status.js' if $UPLOAD_PROGRESS
	    html.style "@import '/control/s/css/control.css';", :type => 'text/css'
	  end
	  html.body do
	    html.div :id => "page" do
	      if @user and not @login
		html.div :class => "menu" do
		  html.ul do
		    html.li { html.a 'buckets', :href => "/control/buckets" }
		    html.li { html.a 'users', :href => "/control/users" } if @user.superuser?
		    html.li { html.a 'profile', :href => "/control/profile" }
		    html.li { html.a 'logout', :href => "/control/logout" }
		  end
		end
	      end
	      html.div :id => "header" do
		html.h1 "Control Center"
		html.h2 str
	      end
	      html.div :id => "content" do
		yield html
	      end
	    end
	  end
	end
      end
    end

    def popup_layout(str)
      builder do |html|
	html.html do
	  html.head do
	    html << "<title>Park Place Control Center &raquo; #{str}</title>"
	    html.script " ", :language => 'javascript', :src => '/control/s/js/prototype.js'
	    html.style "@import '/control/s/css/control.css';", :type => 'text/css'
	  end
	end
	html.body do
	  html.div :id => "content" do
	    yield html
	  end
	end
      end
    end

    def login_view
      default_layout("Login") do |html|
	html.form :method => "post", :class => "create" do
	  html.div :class => "required" do
	    html.label 'User', :for => "login"
	    html.input :type => "text", :name => "login", :id => "login"
	  end
	  html.div :class => "required" do
	    html.label 'Password', :for => "password"
	    html.input :type => "password", :name => "password", :id => "password"
	  end
	  html.input :type => "submit", :value => "Login", :id => "loggo", :name => "loggo"
	end
      end
    end

    def bucket_view
      default_layout("My Buckets") do |html|
	if @buckets.any?
	  html.table do
	    html.thead do
	      html.tr do
		html.th "Name"
		html.th "Contains"
		html.th "Updated on"
		html.th "Info"
		html.th "Actions"
	      end
	    end
	    html.tbody do
	      @buckets.each do |bucket|
	        html.tr do
		  html.th do
		    html.div { html.a bucket.name, :href => "/control/buckets/#{bucket.name}" }
		  end
		  html.td "#{bucket.total_children rescue 0} files"
		  html.td bucket.updated_at
		  html.td bucket.access_readable + (bucket.versioning_enabled? ? ",versioned" : "")
		  html.td { html.a "Delete", :href => "/control/delete/#{bucket.name}", :onClick => POST, :title => "Delete bucket #{bucket.name}" }
  	        end
	      end
	    end
	  end
	else
	  html.p "A sad day.  You have no buckets yet."
	end
	html.h3 "Create a Bucket"
	html.form :method => "post", :class => "create" do
	  html << errors_for(@bucket)
	  html.input :name => 'bucket[owner_id]', :type => 'hidden', :value => @bucket.owner_id
	  html.div :class => "required" do
	    html.label 'Bucket Name', :for => 'bucket[name]'
	    html.input :name => 'bucket[name]', :type => 'text', :value => @bucket.name
	  end
	  html.div :classs => "required" do
	    html.label 'Permissions', :for => 'bucket[access]'
	    html.select :name => 'bucket[access]' do
	      CANNED_ACLS.sort.each do |acl, perm|
		opts = {:value => perm}
		opts[:selected] = true if perm == @bucket.access
		html.option acl, opts
	      end
	    end
	  end
	  html.input :type => 'submit', :value => "Create", :id => "newbucket", :name => "newbucket"
	end
      end
    end

    def files_view
      default_layout("/#{@bucket.name}") do |html|
	html.p "Click on a file name to get file details."
	html.table do
	  html.caption do
	    if defined?(Git)
	      html.span :style => "float:right" do
		if !@bucket.versioning_enabled?
		  html.a "Enable Versioning For This Bucket", :href=> "/control/buckets/#{@bucket.name}/versioning", :onClick => POST
		else
		  html.span "Versioning Enabled"
		end
	      end
	    end
	    html << "<a href=\"/control/buckets\">&larr; Buckets</a>"
	  end
	  html.thead do
	    html.tr do
	      html.th "File"
	      html.th "Size"
	      html.th "Permission"
	    end
	  end
	  html.tbody do
	    if @files.empty?
	      html.tr { html.td "No Files", :colspan => "3", :style => "padding:15px;text-align:center" }
	    end
	    @files.each do |file|
	      html.tr do
		html.td do
		  html.a file.name, :href => "javascript://", :onclick => "$('details-#{file.id}').toggle()"
		  html.div :class => "details", :id => "details-#{file.id}", :style => "display:none" do
		    html.p "Revision: #{file.git_object.objectish}" if @bucket.versioning_enabled? && !file.git_object.nil?
		    if file.torrent
		      html << "<p>" + ["#{file.torrent.seeders} seeders",
			"#{file.torrent.leechers} leechers",
			"#{file.torrent.total} downloads" ].join(" &bull; ") + "</p>"
		    end
		    html.p "Last modified on #{file.updated_at}"
		    html.p do
		      info = ["<a href=\"" + signed_url("/#{@bucket.name}/#{file.name}") + "\" target=\"_blank\">Get</a>"]
		      info += ["<a href=\"/control/acl/#{@bucket.name}/#{file.name}\" onclick=\"#{POPUP}\">Access</a>"]
		      info += ["<a href=\"/control/meta/#{@bucket.name}/#{file.name}\" onclick=\"#{POPUP}\">Meta</a>"]
		      info += ["<a href=\"/control/changes/#{@bucket.name}/#{file.name}\" onclick=\"#{POPUP}\">Changes</a>"] if @bucket.versioning_enabled?
		      info += ["<a href=\"" + signed_url("/#{@bucket.name}/#{file.name}") + "&torrent\" target=\"_blank\">Torrent</a>"] if defined?(RubyTorrent)
		      info += ["<a href=\"/control/delete/#{@bucket.name}/#{file.name}\" onclick=\"#{POST}\" title=\"Delete file #{file.name}\">Delete</a>"]
		      html << info.join(" &bull; ")
		    end
		  end
		end
		html.td number_to_human_size(file.size)
		html.td file.access_readable
	      end
	    end
	  end
	end
	html.div :id => "results" do
	end
	html.div :id => "progress-bar", :style => "display:none" do
	end
	html.iframe :id => "upload", :name => "upload", :style => "display:none" do
	end

	@upid = Time.now.to_f
	form_options = { :action => "?upload_id=#{@upid}", :id => "upload-form", :method => 'post', :enctype => 'multipart/form-data', :class => 'create' }
	form_options.merge!({ :onsubmit => "UploadProgress.monitor('#{@upid}')", :target => "upload" }) if $UPLOAD_PROGRESS
	html.form form_options do
	  html.h3 "Upload a File"
	  html.div :class => "required" do
	    html.input :name => 'upfile', :type => 'file'
	  end
	  html.div :class => "optional" do
	    html.label 'File Name', :for => 'fname'
	    html.input :name => 'fname', :type => 'text'
	  end
	  html.div :class => "required" do
	    html.label 'Permissions', :for => 'facl'
	    html.select :name => 'facl' do
	      CANNED_ACLS.sort.each do |acl, perm|
		opts = {:value => perm}
		opts[:selected] = true if perm == @bucket.access
		html.option acl, opts
	      end
	    end
	  end
	  html.input :type => 'submit', :value => "Create", :id => "newfile", :name => "newfile"
	end
      end
    end

    def users_view
      default_layout("User List") do |html|
	html.table do
	  html.thead do
	    html.tr do
	      html.th "Login"
	      html.th "Activated On"
	      html.th "Total Storage"
	      html.th "Actions"
	    end
	  end
	  html.body do
	    @users.each do |user|
	      html.tr do
		html.th { html.a user.login, :href => "/control/users/#{user.login}" }
		html.td user.activated_at
		html.td number_to_human_size(Bit.sum(:size, :conditions => [ 'owner_id = ?', user.id ]))
		html.td { html.a "Delete", :href => "/control/users/delete/#{user.login}", :onclick => POST, :title => "Delete user #{user.login}" }
	      end
	    end
	  end
	end
	html.h3 "Create a User"
	html.form :action => "/control/users", :method => 'post', :class => 'create' do
	  html << errors_for(@usero)
	  html.div :class => "required" do
	    html.label 'Login', :for => 'user[login]'
	    html.input :name => 'user[login]', :type => 'text', :value => @usero.login, :class => "large"
	  end
	  html.div :class => "required inline" do
	    html.label 'Is a super-admin? ', :for => 'user[superuser]'
	    html.input :type => 'checkbox', :name => 'user[superuser]', :value => @usero.superuser
	  end
	  html.div :class => "required" do
	    html.label 'Password', :for => 'user[password]'
	    html.input :name => 'user[password]', :type => 'password', :class => "fixed"
	  end
	  html.div :class => "required" do
	    html.label 'Password again', :for => 'user[password_confirmation]'
	    html.input :name => 'user[password_confirmation]', :type => 'password', :class => "fixed"
	  end
	  html.div :class => "required" do
	    html.label 'Email', :for => 'user[email]'
	    html.input :name => 'user[email]', :type => 'text', :value => @usero.email
	  end
	  html.div :class => "required" do
	    html.label 'Key (must be unique)', :for => 'user[key]'
	    html.input :name => 'user[key]', :type => 'text', :class => "fixed long", :value => @usero.key || generate_key
	  end
	  html.div :class => "required" do
	    html.label 'Secret', :for => 'user[secret]'
	    html.input :name => 'user[secret]', :class => "fixed long", :type => 'text', :value => @usero.secret || generate_secret
	  end
	  html.input :type => 'submit', :value => "Create", :name => "newuser", :id => "newuser"
	end
      end
    end

    def profile_view
      default_layout(@usero.id == @user.id ? "Your Profile" : @usero.login) do |html|
	html.form :method => 'post', :class => 'create' do
	  html << errors_for(@usero)
	  if @user.superuser?
	    html.div :class => "required inline" do
	      html.label 'Is a super-admin? ', :for => 'user[superuser]'
	      html.input :type => 'checkbox', :name => 'user[superuser]', :value => @usero.superuser
	    end
	  end
	  html.div :class => "required" do
	    html.label 'Password', :for => 'user[password]'
	    html.input :name => 'user[password]', :type => 'password', :class => "fixed"
	  end
	  html.div :class => "required" do
	    html.label 'Password again', :for => 'user[password_confirmation]'
	    html.input :class => 'fixed', :name => 'user[password_confirmation]', :type => 'password'
	  end
	  html.div :class => "required" do
	    html.label 'Email', :for => 'user[email]'
	    html.input :name => 'user[email]', :type => 'text', :value => @usero.email
	  end
	  html.div :class => "required" do
	    html.label 'Key', :for => 'key'
	    html.h4 @usero.key
	  end
	  html.div :class => "required" do
	    html.label 'Secret', :for => 'secret'
	    html.h4 @usero.secret
	  end
	  html.input :type => 'submit', :value => "Save", :id => "newfile", :name => "newfile"
	end
      end
    end

    def meta_view
      popup_layout("") do |html|
	html.form :method => 'post', :class => 'create', :style => "text-align:left" do
	  html << errors_for(@slot)
	  html.table do
	    html.thead do
	      html.tr do
	        html.th "Key"
	        html.th "Value"
	      end
	    end
	    html.tbody do
	      if @slot.meta.empty?
		html.tr { html.td "No Metadata", :colspan => "2", :style => "padding:8px;text-align:center" }
	      else
	        @slot.meta.each do |k,v|
	          html.tr do
	  	    html.td k
		    html.td { html.input :name => "m[#{k}]", :type => "text", :value => v, :style => "width:100%" }
	          end
	        end
	      end
	    end
	    html.thead { html.tr { html.th "New Key", :colspan => "2" } }
	    html.tbody do
	      html.tr do
		html.td do
		  html.input :name => "meta[key]", :type => "text", :style => "width:100%"
		end
		html.td do
		  html.input :name => "meta[value]", :type => "text", :style => "width:100%"
		end
	      end
	    end
	  end
	  html.div :style => "text-align:center;margin-top:15px" do
	    html.input :type => "submit", :value => "Update"
	  end
	end
      end
    end

    def edit_view
      default_layout(@slot.name) do |html|
	html.form :method => 'post', :class => 'create' do
	  html.textarea "", :name => "slot[file_data]", :style => "width:100%;height:20em"
	  html.div :class => "required" do
	    html.label "Content-Type", :for => "slot[content_type]"
	    html.input :name => "slot[content_type]", :type => "text", :value => @slot.obj.mime_type
	  end
	  html.input :type => "submit", :value => "Update"
	end
      end
    end

    def acl_view
      popup_layout("") do |html|
	html.table do
	  html.thead do
	    html.tr do
	      html.th "For"
	      html.th "Access"
	    end
	  end
	  html.tbody do
	    @slot.acl_list.each_pair do |key,acl|
	      html.tr do
		html.td acl[:type] == "CanonicalUser" ? "#{acl[:id]} (#{acl[:name]})" : acl[:uri].split("/").last
		html.td acl[:access]
	      end
	    end
	  end
	end
	html.div :style => "text-align:left;margin-top:10px" do
	  html.h3 "Modify File Access"
	  html.form :class => "create", :method => "post" do
	    html.div :class => "required" do
	      html.label "For", :for => "acl_type"
	      html.select :name => "acl[type]", :id => "acl_type", :onchange => "$('user_id_box').style.display = this.value == 'email' ? 'block' : 'none';" do
		html.option "AllUsers", :value => "http://acs.amazonaws.com/groups/global/AllUsers"
		html.option "AuthenticatedUsers", :value => "http://acs.amazonaws.com/groups/global/AuthenticatedUsers"
		html.option "By ID/E-Mail", :value => "email"
	      end
	    end
	    html.div :class => "required", :style => "display:none", :id => "user_id_box" do
	      html.label "User ID / E-Mail", :for => "user_id"
	      html.input :type => "text", :name => "acl[user_id]", :id => "user_id"
	    end
	    html.div :class => "required" do
	      html.label "Access", :for => "user_access"
	      html.select :name => "acl[access]", :id => "user_access" do
		html.option "READ", :value => "READ"
		html.option "READ_ACP", :value => "READ_ACP"
		html.option "WRITE", :value => "WRITE"
		html.option "WRITE_ACP", :value => "WRITE_ACP"
	      end
	    end
	    html.input :type => "submit", :value => "Update"
	  end
	end
      end
    end

    def changes_view
      popup_layout("") do |html|
	html.table do
	  html.thead do
	    html.tr do
	      html.th "Commit Log For #{@file.name}"
	    end
	  end
	  html.tbody do
	    @versions.each do |version|
	      html.tr do
		html.td do
		  html.div { html.a version.sha, :target => "_blank", :href => signed_url("/#{@bucket.name}/#{@file.name}") + "&version-id=#{version.sha}" }
		  html.div "On: #{version.date}"
		  html.div "By: #{version.author.name} <#{version.author.email}>"
		end
	      end
	    end
	  end
	end
      end
    end

  end

end
