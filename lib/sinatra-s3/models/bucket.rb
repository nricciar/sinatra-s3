class Bucket < Bit

  named_scope :user_buckets, lambda { |uid| { :conditions => ['parent_id IS NULL AND owner_id = ?', uid ], :order => "name" } }
  named_scope :root, lambda { |name| { :conditions => ['deleted = 0 AND parent_id IS NULL AND name = ?', name] } }

  def items(marker,prefix)
    Slot.bucket(self).items(marker,prefix)
  end

  def self.find_root(bucket_name)
    root(bucket_name).find(:first) or raise S3::NoSuchBucket
  end

  def find_slot(oid)
    Slot.find(:first, :conditions => ['deleted = 0 AND parent_id = ? AND name = ?', self.id, oid]) or raise S3::NoSuchKey
  end

  def remove_from_filesystem
    bucket_dir = File.join(S3::STORAGE_PATH, self.name)
    FileUtils.rm_rf bucket_dir if File.directory?(bucket_dir) && Dir.empty?(bucket_dir)
  end

  def git_disable
    FileUtils.touch(File.join(self.fullpath, '.git', 'disable_versioning'))
  end

  def add_child(bit)
    bit.update_attributes(:parent_id => self.id)
  end

  def git_init
    disable_file = File.join(self.fullpath, '.git', 'disable_versioning')
    FileUtils.rm_f(disable_file) and return if File.exists?(disable_file)

    begin
      FileUtils.mkdir_p(self.fullpath) unless File.exists?(self.fullpath)
      dir_empty = !Dir.foreach(self.fullpath) {|n| break true unless /\A\.\.?\z/ =~ n}
      g = Git.init(self.fullpath)
      g.config('user.name', self.owner.login)
      g.config('user.email', self.owner.email)
      # if directory is not empty we need to add the files
      # into version control
      unless dir_empty
	g.add('.')
	g.commit_all("Enabling versioning for bucket #{self.name}.")
	self.git_update
      end
      self.type = "GitBucket"
      self.save()
      self.git_update
    rescue Git::GitExecuteError => error_message
      puts "[#{Time.now}] GIT: #{error_message}" 
    end
  end

  def metainfo
    children = self.all_children
    mii = RubyTorrent::MetaInfoInfo.new
    mii.name = self.name
    mii.piece_length = 512.kilobytes
    mii.files, files = [], []
    mii.pieces = ""
    i = 0
    Slot.find(:all, :conditions => ['parent_id = ?', self.id]).each do |slot|
      miif = RubyTorrent::MetaInfoInfoFile.new
      miif.length = slot.obj.size
      miif.md5sum = slot.obj.md5
      miif.path = File.split(slot.name)
      mii.files << miif
      files << slot.fullpath
    end
    each_piece(files, mii.piece_length) do |piece|
      mii.pieces += Digest::SHA1.digest(piece)
      i += 1
    end
    mi = RubyTorrent::MetaInfo.new
    mi.info = mii
    mi
  end

end
