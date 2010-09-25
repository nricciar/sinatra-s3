class CreateBits < ActiveRecord::Migration

  def self.up
    create_table :bits do |t|
      t.column :id,        :integer,  :null => false
      t.column :owner_id,  :integer
      t.column :parent_id, :integer
      t.column :lft,       :integer
      t.column :rgt,       :integer
      t.column :type,      :string,   :limit => 6
      t.column :name,      :string,   :limit => 255
      t.column :created_at, :timestamp
      t.column :updated_at, :timestamp
      t.column :access,    :integer
      t.column :meta,      :text
      #t.column :obj,       :text
      t.column :size,      :integer, :default => 0
      t.column :version,   :string
      t.column :deleted,   :integer, :default => 0
    end
    add_index :bits, :name
  end

  def self.down
    drop_table :bits
  end

end
