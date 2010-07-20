require 's3'

use S3::S3Tracker if defined?(RubyTorrent)
use S3::S3Admin
run S3::Application
