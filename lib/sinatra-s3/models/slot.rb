class Slot < Bit

  scope :bucket, lambda { |bucket| { :conditions => [ 'bits.deleted = 0 AND parent_id = ?', bucket.id ], :order => "name" } }
  scope :items, lambda { |marker,prefix| { :conditions => condition_string(marker,prefix) } }

  def fullpath; File.join(S3::STORAGE_PATH, file_info.path) end

  def etag
    if self.file_info.etag
      self.file_info.etag
    elsif self.file_info.md5
      self.file_info.md5
    else
      %{"#{MD5.md5(self.file_info)}"}
    end
  end

  def remove_from_filesystem
    FileUtils.rm_f fullpath
  end

  def metainfo
    mii = RubyTorrent::MetaInfoInfo.new
    mii.name = self.name
    mii.length = self.file_info.size
    mii.md5sum = self.file_info.md5
    mii.piece_length = 512.kilobytes
    mii.pieces = ""
    i = 0
    each_piece([self.fullpath], mii.piece_length) do |piece|
      mii.pieces += Digest::SHA1.digest(piece)
      i += 1
    end
    mi = RubyTorrent::MetaInfo.new
    mi.info = mii
    mi
  end

  protected
  def self.condition_string(marker,prefix)
    conditions = []
    conditions << "name LIKE '#{prefix.gsub(/\\/, '\&\&').gsub(/'/, "''")}%'" unless prefix.blank?
    conditions << "name > '#{marker.gsub(/\\/, '\&\&').gsub(/'/, "''")}'" unless marker.blank?
    conditions.empty? ? nil : conditions.join(" AND ")
  end

end
