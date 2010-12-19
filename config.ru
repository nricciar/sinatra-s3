$:.unshift "./lib"
ENV['AWS_AUTH_PATH'] ||= File.expand_path(File.join(File.dirname(__FILE__),'s3.yml'))
require 'sinatra-s3'

AWS::Admin.home_page = "/control/buckets"
use AWSAuth::Base

# AWS Base
map '/control' do
  run AWS::Admin
end

# S3
map '/' do
  use S3::Tracker if defined?(RubyTorrent)
  run S3::Application
end
