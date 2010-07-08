module S3
  module Helpers
    module Versioning

      def versioning_response_for(bit)
	xml do |x|
	  x.VersioningConfiguration :xmlns => "http://s3.amazonaws.com/doc/2006-03-01/" do
	    x.Versioning bit.versioning_enabled? ? 'Enabled' : 'Suspended'
	  end
	end
      end

    end
  end
end
