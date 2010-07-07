require File.join(File.dirname(__FILE__), '..', 'helpers.rb')

class User < ActiveRecord::Base

  include S3::Helpers

  has_many :bits, :foreign_key => 'owner_id'
  has_many :bits_users

  validates_length_of :login, :within => 3..40
  validates_uniqueness_of :login
  validates_uniqueness_of :key
  validates_presence_of :password
  validates_confirmation_of :password

  def destroy
    self.deleted = 1
    self.save
  end

  attr_accessor :skip_before_save

  protected
  def before_save
    unless self.skip_before_save
      @password_clean = self.password
      self.password = hmac_sha1(self.password, self.secret)
    end
  end

  def after_save
    self.password = @password_clean
  end

end
