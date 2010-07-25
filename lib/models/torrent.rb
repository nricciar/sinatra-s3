class Torrent < ActiveRecord::Base

  belongs_to :bit
  has_many :torrent_peers

end
