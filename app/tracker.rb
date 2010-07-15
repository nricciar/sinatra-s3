module S3

  TRACKER_INTERVAL = 10.minutes

  # All tracker errors are thrown as this class.
  class TrackerError < Exception; end

  class S3Tracker < Sinatra::Base

    helpers do
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

    end

    get '/tracker/scrape/?' do

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
		  html.td t.metainfo.creation_date
		end
	      end
	    end
	  end
	end
      end
    end
  end

end
