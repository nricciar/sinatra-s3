class Bit < ActiveRecord::Base

  has_many :bits_users

  serialize :meta
  serialize :obj

  belongs_to :parent, :class_name => 'Bit', :foreign_key => 'parent_id'
  belongs_to :owner, :class_name => 'User', :foreign_key => 'owner_id'

  validates_length_of :name, :within => 3..255

  has_one :torrent

  def git_repository
    versioning_enabled? ? Git.open(git_repository_path) : nil
  end

  def fullpath; File.join(STORAGE_PATH, name) end

  def git_repository_path
    self.obj ? File.join(File.dirname(self.fullpath)) : self.fullpath
  end

  def versioning_enabled?
    return false if !defined?(Git) || !File.exists?(File.join(git_repository_path,'.git'))
    return false if File.exists?(File.join(git_repository_path,'.git', 'disable_versioning'))
    return true
  end

  def git_object
    git_repository.log.path(File.basename(self.obj.path)).first if versioning_enabled? && self.obj
  end

  def objectish
    git_repository.gcommit(version).gtree.blobs[File.basename(fullpath)].objectish
  end

  def diff(to)
    to = Bit.find_by_version(to) if to.instance_of?(String)
    git_repository.diff(objectish, to.objectish)
  end

  def self.diff(from,to)
    from = Bit.find_by_version(from)
    to = Bit.find_by_version(to)
    from.git_repository.diff(from.objectish, to.objectish)
  end

  def acl_list
    bit_perms = self.access.nil? ? "000" : self.access.to_s(8)
    acls = { :owner => { :id => self.owner.key, :accessnum => 7, :type => "CanonicalUser", :name => self.owner.login, :access => "FULL_ACCESS" },
      :anonymous => { :id => nil, :accessnum => bit_perms[2,1], :access => acl_label(bit_perms[2,1]),
	:type => "Group", :uri => "http://acs.amazonaws.com/groups/global/AllUsers" },
	:authenticated => { :id => nil, :accessnum => bit_perms[1,1], :access => acl_label(bit_perms[1,1]),
	  :type => "Group", :uri => "http://acs.amazonaws.com/groups/global/AuthenticatedUsers" }
    }.merge(get_acls_for_bin)
    acls.delete_if { |key,value| value[:access] == "NONE" || (key == :authenticated && (!acls[:anonymous].nil? && value[:accessnum] <= acls[:anonymous][:accessnum])) }
  end

  def get_acls_for_bin
    ret = {}
    for a in self.bits_users
      ret[a.user.key] = { :type => "CanonicalUser", :id => a.user.key, :name => a.user.login, :access => acl_label(a.access.to_s(8)[0,1]),
	:accessnum => a.access.to_s(8)[0,1] }
    end
    ret
  end

  def self.acl_text
    { 0 => "NONE", 1 => "NONE", 2 => "NONE", 3 => "NONE", 4 => "READ", 5 => "READ_ACP", 6 => "WRITE", 7 => "WRITE_ACP" }
  end

  def acl_label(num)
    Bit.acl_text[num.to_i]
  end

  def grant hsh
    if hsh[:access]
      self.access = hsh[:access]
      self.save
    end
  end

  def access_readable
    name, _ = CANNED_ACLS.find { |k, v| v == self.access }
    if name
      name
    else
      [0100, 0010, 0001].map do |i|
	[[4, 'r'], [2, 'w'], [1, 'x']].map do |k, v|
	  (self.access & (i * k) == 0 ? '-' : v )
	end
      end.join
    end
  end

  def acp_readable_by? user
    # if owner
    return true if user && user == owner
    # if can write or better
    return true if user && acl_list[user.key] && acl_list[user.key][:accessnum].to_i >= 5
    # if authenticated
    return true if user && acl_list[:authenticated] && acl_list[:authenticated][:accessnum].to_i >= 5
    # if anonymous
    return true if acl_list[:anonymous] && acl_list[:anonymous][:accessnum].to_i >= 5
  end

  def acp_writable_by? user
    # if owner
    return true if user && user == owner
    # if can write or better
    return true if user && acl_list[user.key] && acl_list[user.key][:accessnum].to_i == 7
    # if authenticated
    return true if user && acl_list[:authenticated] && acl_list[:authenticated][:accessnum].to_i == 7
    # if anonymous
    return true if acl_list[:anonymous] && acl_list[:anonymous][:accessnum].to_i == 7
  end

  def readable_by? user
    return true if user && acl_list[user.key] && acl_list[user.key][:accessnum].to_i >= 4
    check_access(user, READABLE_BY_AUTH, READABLE)
  end

  def writable_by? user
    return true if user && acl_list[user.key] && acl_list[user.key][:accessnum].to_i >= 6
    check_access(user, WRITABLE_BY_AUTH, WRITABLE)
  end

  def check_access user, group_perm, user_perm
    !!( if owned_by?(user) or (user and access & group_perm > 0) or (access & user_perm > 0)
       true
    elsif user
      acl = users.find(user.id) rescue nil
      acl and acl.access.to_i & user_perm
    end )
  end

  def owned_by? user
    user and owner_id == user.id
  end

  def git_update
    # update git info so we can serve it over http
    base_dir = File.join(self.git_repository_path,'.git')
    if File.exists?(base_dir)
      File.open(File.join(base_dir,'HEAD'),'w') { |f| f.write("ref: refs/heads/master") }
      if File.exists?(File.join(base_dir,'refs/heads/master'))
        File.open(File.join(base_dir,'info/refs'),'w') { |f|
  	  ref = File.open(File.join(base_dir,'refs/heads/master')) { |re| re.read }
	  f.write("#{ref.chomp}\trefs/heads/master\n")
        }
      end
    end
  end

  def each_piece(files, length)
     buf = ""
     files.each do |f|
         File.open(f) do |fh|
             begin
                 read = fh.read(length - buf.length)
                 if (buf.length + read.length) == length
                     yield(buf + read)
                     buf = ""
                 else
                     buf += read
                 end
             end until fh.eof?
         end
     end
     yield buf
  end

end

class BitsUser < ActiveRecord::Base
  belongs_to :bit
  belongs_to :user
end
