module S3
  module Helpers
    module Versioning

      def versioning_response_for(bit)
	xml do |x|
	  x.VersioningConfiguration :xmlns => "http://s3.amazonaws.com/doc/2006-03-01/" do
	    x.Versioning bit.versioning_enabled? ? 'Enabled' : 'Suspended' if File.exists?(File.join(bit.fullpath, '.git'))
	  end
	end
      end

      def manage_versioning(bucket)
	raise NotImplemented unless defined?(Git)
	only_can_write_acp bucket

	env['rack.input'].rewind
	data = env['rack.input'].read
	xml_request = REXML::Document.new(data).root

	bucket.git_init() if !bucket.versioning_enabled? && xml_request.elements['Status'].text == 'Enabled'
	bucket.git_destroy() if bucket.versioning_enabled? && xml_request.elements['Status'].text == 'Suspended'
      end

    end
  end
end
