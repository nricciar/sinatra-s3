require 'rubygems'
require 'bundler'

Bundler.require

$:.unshift "./lib"
require 'sinatra-s3'

use S3::Tracker if defined?(RubyTorrent)
use S3::Admin
run S3::Application
