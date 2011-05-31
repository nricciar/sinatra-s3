require 'aws/s3'
require "sinatra/reloader"

module S3

  class Admin < Sinatra::Base

    helpers do
      include S3::Helpers
      include S3::AdminHelpers
    end

    set :sessions, :on
    set :environment, S3_ENV
    set :views, File.join(File.dirname(__FILE__), 'views')

    configure(:development) do
      register Sinatra::Reloader
      also_reload "./lib/**/*.rb"
    end

    before do
      ActiveRecord::Base.verify_active_connections!
    end

    get '/control/?' do
      login_required
      redirect '/control/buckets'
    end

    get %r{^/control/s/(.*)} do
      expires 500, :public
      open(File.join(ROOT_DIR, 'public', params[:captures].first))
    end

    get '/control/login' do
      r :login, "Login"
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
      r :buckets, "Buckets"
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
      r :buckets, "Buckets"
    end

    get '/control/buckets/:bucket/?' do
      login_required
      @bucket = Bucket.find_root(params[:bucket])
      only_can_read @bucket
      @files = Slot.find :all, :conditions => ['deleted = 0 AND parent_id = ?', @bucket.id], :order => 'name'
      r :files, "/#{@bucket.name}"
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
      readlen, md5 = 0, Digest::MD5.new
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
        fileinfo.path = slot.fileinfo.path
        file_path = File.join(STORAGE_PATH,fileinfo.path)

        slot.update_attributes(:owner_id => @user.id, :meta => mdata, :size => fileinfo.size)
        slot.file_info.attributes = fileinfo.attributes

        FileUtils.mv(tmpf.path, file_path,{ :force => true })
      rescue NoSuchKey
        fileinfo.path = File.join(params[:bucket], rand(10000).to_s(36) + '_' + File.basename(tmpf.path))
        fileinfo.path.succ! while File.exists?(File.join(STORAGE_PATH, fileinfo.path))
        file_path = File.join(STORAGE_PATH,fileinfo.path)
        FileUtils.mkdir_p(File.dirname(file_path))
        FileUtils.mv(tmpf.path, file_path)

        slot = Slot.create(:name => params['fname'], :owner_id => @user.id, :meta => mdata, :size => fileinfo.size)
        slot.file_info = fileinfo
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
      @versions = @bucket.git_repository.log.path(File.basename(@file.file_info.path))
      r :changes, "Commit Log", :popup
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
        @slot.git_repository.remove(File.basename(@slot.file_info.path))
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
      r :profile, "Your Profile"
    end

    post "/control/profile/?" do
      login_required
      @user.update_attributes(params['user'])
      @usero = @user
      r :profile, "Your Profile"
    end

    get "/control/users/?" do
      login_required
      only_superusers
      @usero = User.new
      @users = User.find :all, :conditions => ['deleted != 1'], :order => 'login'
      r :users, "User List"
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
        r :users, "User List"
      end
    end

    get "/control/users/:login/?" do
      login_required
      only_superusers
      @usero = User.find_by_login params[:login]
      r :profile, @usero.login
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
        r :profile, @usero.login
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

    get %r{^/control/acl/(.+?)/(.+)$} do
      login_required
      @bucket = Bucket.find_root(params[:captures].first)
      only_can_write_acp @bucket
      @slot = @bucket.find_slot(params[:captures].last)
      only_can_write @slot
      r :acl, "Modify File Access", :popup
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
      r :meta, "Metadata", :popup
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
      r :meta, "Metadata", :popup
    end

  end

end
