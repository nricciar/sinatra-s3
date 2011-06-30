class TwoFactorAuth < ActiveRecord::Migration

  def self.up
    add_column :users, :google_auth_key, :string, :limit => 32
  end

  def self.down
    remove_column :users, :google_auth_key
  end

end

