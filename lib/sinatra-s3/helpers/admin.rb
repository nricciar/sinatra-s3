require 'aws/s3'

module S3
  module AdminHelpers

    def login_required
      @user = AWSAuth::User.find(session[:user_id]) unless session[:user_id].nil?
      redirect '/control/login' if @user.nil?
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

    def signed_url(path)
      url = "#{path}?"
      url + AWS::S3::Authentication::QueryString.new(Net::HTTP::Get.new(path), @user.key, @user.secret)
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
