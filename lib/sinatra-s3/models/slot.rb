class Slot < Bit

  named_scope :bucket, lambda { |bucket| { :conditions => [ 'bits.deleted = 0 AND parent_id = ?', bucket.id ], :order => "name" } }
  named_scope :items, lambda { |marker,prefix| { :conditions => condition_string(marker,prefix) } }

  def fullpath; File.join(S3::STORAGE_PATH, obj.path) end

  def etag
    if self.obj.respond_to? :etag
      self.obj.etag
    elsif self.obj.respond_to? :md5
      self.obj.md5
    else
      %{"#{Digest::MD5.md5(self.obj)}"}
    end
  end

  def remove_from_filesystem
    FileUtils.rm_f fullpath
  end

  def metainfo
    mii = RubyTorrent::MetaInfoInfo.new
    mii.name = self.name
    mii.length = self.obj.size
    mii.md5sum = self.obj.md5
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
