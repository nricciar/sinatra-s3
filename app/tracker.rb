module S3

  TRACKER_INTERVAL = 10.minutes
  EVENT_CODES = {
    'started' => 200,
    'completed' => 201,
    'stopped' => 202
  }
  # All tracker errors are thrown as this class.
  class TrackerError < Exception; end

  class S3Tracker < Sinatra::Base

    helpers do
      include S3::AdminHelpers
      include S3::TrackerHelper
    end

    configure do
      ActiveRecord::Base.establish_connection(S3.config[:db])
    end

    before do
      ActiveRecord::Base.verify_active_connections!
    end

    get '/tracker/announce/?' do
      raise TrackerError, "No info_hash present." unless params[:info_hash]
      raise TrackerError, "No peer_id present." unless params[:peer_id]

      info_hash = params[:info_hash].to_hex_s
      guid = params[:peer_id].to_hex_s
      trnt = Torrent.find_by_info_hash(info_hash)
      raise TrackerError, "No file found with hash of `#{params[:info_hash]}'." unless trnt

      peer = TorrentPeer.find_by_guid_and_torrent_id(guid, trnt.id)
      unless peer
	peer = TorrentPeer.find_by_ipaddr_and_port_and_torrent_id(env['REMOTE_ADDR'], params[:port], trnt.id)
      end
      unless peer
	peer = TorrentPeer.new(:torrent_id => trnt.id)
	trnt.hits += 1
      end

      trnt.total += 1 if params[:event] == "completed"
      params[:event] = 'completed' if params[:left] == 0
      if params[:event]
	peer.update_attributes(:uploaded => params[:uploaded], :downloaded => params[:downloaded],
	  :remaining => params[:left], :event => EVENT_CODES[params[:event]], :key => params[:key],
	  :port => params[:port], :ipaddr => env['REMOTE_ADDR'], :guid => guid)
      end
      complete, incomplete = 0, 0
      peers = trnt.torrent_peers.map do |peer|
	if peer.updated_at < Time.now - (TRACKER_INTERVAL * 2) or (params[:event] == 'stopped' and peer.guid == guid)
	  peer.destroy
	  next
	end
	if peer.event == EVENT_CODES['completed']
	  complete += 1
	else
	  incomplete += 1
	end
	next if peer.guid == guid
	{'peer id' => peer.guid.from_hex_s, 'ip' => peer.ipaddr, 'port' => peer.port}
      end.compact
      trnt.seeders = complete
      trnt.leechers = incomplete
      trnt.save
      tracker_reply('peers' => peers, 'complete' => complete, 'incomplete' => incomplete)
    end

    get '/tracker/scrape/?' do
      @torrents = torrent_list params[:info_hash]
      tracker_reply('files' => @torrents.map { |t|
	{'complete' => t.seeders, 'downloaded' => t.total, 'incomplete' => t.leechers, 'name' => t.bit.name} })
    end

    get '/tracker/?' do
      @torrents = torrent_list params[:info_hash]
      @transfer = TorrentPeer.sum :downloaded, :group => :torrent
      torrent_view
    end

    protected
    def torrent_view
      builder do |html|
	html.html do
	  html.head do
	    html.title "Sinatra-S3 Torrents"
	  end
	end
	html.body do
	  html.table do
	    html.thead do
	      html.tr do
		html.th "Name"
		html.th "Size"
		html.th "Seeders"
		html.th "Leechers"
		html.th "Downloads"
		html.th "Transfered"
		html.th "Since"
	      end
	    end
	    html.tbody do
	      @torrents.each do |t|
		html.tr do
		  html.td t.bit.name
		  html.td number_to_human_size(t.bit.size)
		  html.td t.seeders
		  html.td t.leechers
		  html.td t.total
		  html.td number_to_human_size(@transfer[t])
		  html.td "" #t.metainfo.creation_date
		end
	      end
	    end
	  end
	end
      end
    end
  end

end
