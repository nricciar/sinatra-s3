class CreateTorrents < ActiveRecord::Migration

  def self.up
    create_table :torrents do |t|
      t.column :id, :integer, :null => false
      t.column :bit_id, :integer
      t.column :info_hash, :string, :limit => 40
      t.column :metainfo, :binary
      t.column :seeders, :integer, :null => false, :default => 0
      t.column :leechers, :integer, :null => false, :default => 0
      t.column :hits, :integer, :null => false, :default => 0
      t.column :total, :integer, :null => false, :default => 0
      t.column :updated_at, :timestamp
    end
  end

  def self.down
    drop_table :torrents
  end

end

