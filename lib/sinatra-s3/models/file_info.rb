class FileInfo
  attr_accessor :path, :mime_type, :disposition, :size, :md5, :etag


  def to_s
    YAML::dump(self)
  end

end
