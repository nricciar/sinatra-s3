$:.unshift "./lib"
require 'rake'
require 'sinatra-s3'

spec = Gem::Specification.new do |s|
  s.name = "sinatra-s3"
  s.version = S3::VERSION
  s.author = "David Ricciardi"
  s.email = "nricciar@gmail.com"
  s.homepage = "http://github.com/nricciar/sinatra-s3"
  s.platform = Gem::Platform::RUBY
  s.summary = "An implementation of the Amazon S3 API in Ruby"
  s.files = FileList["{bin,lib,examples}/**/*"].to_a +
    FileList["db/migrate/*"].to_a +
    ["Rakefile","s3.yml.example"]
  s.require_path = "lib"
  s.description = File.read("README")
  s.executables = ['sinatra-s3']
  s.test_files = FileList["{test}/*.rb"].to_a
  s.has_rdoc = false
  s.extra_rdoc_files = ["README"]
  s.add_dependency("sinatra", ">= 1.0")
  s.add_dependency("aws-auth")
  s.add_dependency("aws-s3", ">= 0.6.2")
  s.add_dependency("haml", ">= 2.2.15")
end
