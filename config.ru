$:.unshift "./lib"
require 's3'

use S3::Tracker if defined?(RubyTorrent)
use S3::Admin
run S3::Application
