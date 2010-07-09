require 'rubygems'
require 'test/unit'
require File.join(File.dirname(__FILE__), '..', 's3')
require 'aws/s3'
require 'rack/test'

admin = User.find_by_login('admin')

AWS::S3::Base.establish_connection!(
  :access_key_id     => admin.key,
  :secret_access_key => admin.secret,
  :port => 6060,
  :server => 'localhost'
)

class Test::Unit::TestCase
  include AWS::S3
  include Rack::Test::Methods
  include S3::Helpers

  def app
    S3::Application
  end

end
