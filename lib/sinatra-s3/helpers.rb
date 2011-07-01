Dir["#{File.dirname(__FILE__)}/helpers/*.rb"].each {|r| require r }
require 'base64'

module S3
  module Helpers

    include ACP
    include Versioning

    # Kick out anonymous users.
    def only_authorized; raise S3::AccessDenied unless @user end
    # Kick out any users which do not have read access to a certain resource.
    def only_can_read bit; raise S3::AccessDenied unless bit.readable_by? @user end
    # Kick out any users which do not have write access to a certain resource.
    def only_can_write bit; raise S3::AccessDenied unless bit.writable_by? @user end
    # Kick out any users which do not own a certain resource.
    def only_owner_of bit; raise S3::AccessDenied unless bit.owned_by? @user end
    # Kick out any non-superusers
    def only_superusers; raise S3::AccessDenied unless @user.superuser? end

    protected
    def load_buckets
      @buckets = Bucket.find_by_sql [%{
               SELECT b.id, b.name, b.updated_at, b.access, COUNT(c.id) AS total_children
               FROM bits b LEFT JOIN bits c ON c.parent_id = b.id AND c.deleted = 0
               WHERE b.deleted = 0 AND b.parent_id IS NULL AND b.owner_id = ?
               GROUP BY b.id, b.name, b.updated_at, b.access ORDER BY b.name}, @user.id]
      @bucket = Bucket.new(:owner_id => @user.id, :access => CANNED_ACLS['private'])
    end

    def xml
      xml = Builder::XmlMarkup.new
      xml.instruct! :xml, :version=>"1.0", :encoding=>"UTF-8"
      yield xml
      content_type 'text/xml'
      body xml.target!
    end

    # Convenient method for generating a SHA1 digest.
    def hmac_sha1(key, s)
      ipad = [].fill(0x36, 0, 64)
      opad = [].fill(0x5C, 0, 64)
      key = key.unpack("C*")
      if key.length < 64 then
        key += [].fill(0, 0, 64-key.length)
      end

      inner = []
      64.times { |i| inner.push(key[i] ^ ipad[i]) }
      inner += s.unpack("C*")

      outer = []
      64.times { |i| outer.push(key[i] ^ opad[i]) }
      outer = outer.pack("c*")
      outer += Digest::SHA1.digest(inner.pack("c*"))

      return Base64::encode64(Digest::SHA1.digest(outer)).chomp
    end

    def generate_secret
      abc = %{ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz}
      (1..40).map { abc[rand(abc.size),1] }.join
    end

    def generate_key
      abc = %{ABCDEF0123456789}
      (1..20).map { abc[rand(abc.size),1] }.join
    end

    def get_prefix(c)
      c.name.sub(params['prefix'], '').split(params['delimiter'])[0] + params['delimiter']
    end

    def r(name, title, layout = :layout)
      @title = title
      haml name, :layout => layout
    end

  end
end
