module S3
  module AdminHelpers

    def login_required
      @user = User.find(session[:user_id]) unless session[:user_id].nil?
      redirect '/control/login' if @user.nil?

      if defined?(GoogleAuthenticator)
        redirect '/control/key' if session[:google_auth].nil? && @user.google_auth_key
      end
    end

    def number_to_human_size(size)
      case
      when size < 1.kilobyte then '%d Bytes' % size
      when size < 1.megabyte then '%.1f KB'  % (size / 1.0.kilobyte)
      when size < 1.gigabyte then '%.1f MB'  % (size / 1.0.megabyte)
      when size < 1.terabyte then '%.1f GB'  % (size / 1.0.gigabyte)
      else                    '%.1f TB'  % (size / 1.0.terabyte)
      end.sub('.0', '')
    rescue
      nil
    end

    def signed_url(url)
      time_s = Time.now + 900
      canonical = ['GET',nil,nil,time_s.to_i.to_s,url]
      signature = hmac_sha1(@user.secret, canonical.map{|v|v.to_s.strip} * "\n")
      "#{url}?AWSAccessKeyId=#{@user.key}&Signature=#{signature}&Expires=#{time_s.to_i}"
    end

    def errors_for(model)
      ret = ""
      if model.errors.size > 0
	ret += "<ul class=\"errors\">"
	model.errors.each_full do |error|
	  ret += "<li>#{error}</li>"
	end
	ret += "</ul>"
      end
      ret
    end

  end
end
