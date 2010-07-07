class CreateUsers < ActiveRecord::Migration

  def self.up
    create_table :users do |t|
      t.column :id,             :integer,  :null => false
      t.column :login,          :string,   :limit => 40
      t.column :password,       :string,   :limit => 40
      t.column :email,          :string,   :limit => 64
      t.column :key,            :string,   :limit => 64
      t.column :secret,         :string,   :limit => 64
      t.column :created_at,     :datetime
      t.column :updated_at,     :timestamp
      t.column :activated_at,   :datetime
      t.column :superuser,      :integer, :default => 0
      t.column :deleted,        :integer, :default => 0
    end
  end

  def self.down
    drop_table :users
  end

end

