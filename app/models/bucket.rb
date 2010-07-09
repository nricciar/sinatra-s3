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
    bucket_dir = File.join(STORAGE_PATH, self.name)
    FileUtils.rm_rf bucket_dir if File.directory?(bucket_dir) && Dir.empty?(bucket_dir)
  end

  def git_disable
    FileUtils.touch(File.join(self.fullpath, '.git', 'disable_versioning'))
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

end
