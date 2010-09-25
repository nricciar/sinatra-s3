#class FileInfo
#  attr_accessor :path, :mime_type, :disposition, :size, :md5, :etag
#end

class FileInfo < ActiveRecord::Base
        belongs_to :bit
end