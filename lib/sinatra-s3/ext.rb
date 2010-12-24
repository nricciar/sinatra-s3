class Dir
  def empty?
    Dir.glob("#{ path }/*", File::FNM_DOTMATCH) do |e|
      return false unless %w( . .. ).include?(File::basename(e))
    end
    return true
  end
  def self.empty? path
    new(path).empty?
  end
end

class String
  def to_hex_s
    unpack("H*").first
  end
  def from_hex_s
    [self].pack("H*")
  end
end

module S3
  module FileSizes

    def kilobyte()
      kilobytes()
    end

    def kilobytes()
      self * 1024
    end

    def megabyte()
      megabytes()
    end

    def megabytes()
      self.kilobytes() * 1024
    end

    def gigabyte()
      gigabytes()
    end

    def gigabytes()
      self.megabytes() * 1024
    end

    def terabyte()
      terabytes()
    end

    def terabytes()
      self.gigabytes() * 1024
    end

  end
end
class Fixnum
  include S3::FileSizes
end
class Float
  include S3::FileSizes
end
