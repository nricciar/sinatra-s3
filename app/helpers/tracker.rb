require 'aws/s3'

module S3
  module TrackerHelper

    def torrent(bit)
      mi = bit.metainfo
      mi.announce = URI("http://#{env['HTTP_HOST']}/tracker/announce")
      mi.created_by = "Served by Sinatra-S3/0.1a"
      mi.creation_date = Time.now
      t = Torrent.find_by_bit_id bit.id
      info_hash = Digest::SHA1.digest(mi.info.to_bencoding).to_hex_s
      unless t and t.info_hash == info_hash
	t ||= Torrent.new
	t.update_attributes(:info_hash => info_hash, :bit_id => bit.id, :metainfo => mi.to_bencoding)
      end
      status 200
      headers 'Content-Disposition' => "attachment; filename=#{bit.name}.torrent;", 'Content-Type' => 'application/x-bittorrent'
      body mi.to_bencoding
    end

    def torrent_list(info_hash)
      params = {:order => 'seeders DESC, leechers DESC', :include => :bit}
      params[:conditions] = ['info_hash = ?', info_hash.to_hex_s] if info_hash
      Torrent.find :all, params
    end

    def tracker_reply(params)
      status 200
      headers 'Content-Type' => 'text/plain'
      body params.merge('interval' => TRACKER_INTERVAL).to_bencoding
    end

    def tracker_error(msg)
      status 200
      headers 'Content-Type' => 'text/plain'
      body ({'failure reason' => msg}.to_bencoding)
    end

  end
end
