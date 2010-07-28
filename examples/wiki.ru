$:.unshift "./lib"
require File.join(File.dirname(__FILE__), "wiki")

use S3::Admin
run S3::Application
