class CreateTorrentPeers < ActiveRecord::Migration

  def self.up
    create_table :torrent_peers do |t|
      t.column :id, :integer, :null => false
      t.column :torrent_id, :integer
      t.column :guid, :string, :limit => 40
      t.column :ipaddr, :string
      t.column :port, :integer
      t.column :uploaded, :integer, :null => false, :default => 0
      t.column :downloaded, :integer, :null => false, :default => 0
      t.column :remaining, :integer, :null => false, :default => 0
      t.column :compact, :integer, :null => false, :default => 0
      t.column :event, :integer, :null => false, :default => 0
      t.column :key, :string, :limit => 55
      t.column :created_at, :timestamp
      t.column :updated_at, :timestamp
    end
  end

  def self.down
    drop_table :torrent_peers
  end

end

