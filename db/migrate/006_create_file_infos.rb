class CreateFileInfos < ActiveRecord::Migration

  def self.up
    create_table :file_infos do |t|
      t.references :bit
      t.string  :path,           :limit => 200
      t.string  :mime_type,      :limit => 100
      t.string  :disposition,    :limit => 100
      t.string  :md5,            :limit => 128
      t.string  :etag,           :limit => 128
      t.integer :size,           :default => 0
    end
  end

  def self.down
    drop_table :file_infos
  end

end

