class CreateBitsUsers < ActiveRecord::Migration

  def self.up
    create_table :bits_users do |t|
      t.column :bit_id,  :integer
      t.column :user_id, :integer
      t.column :access,  :integer
    end
  end

  def self.down
    drop_table :bits_users
  end

end

