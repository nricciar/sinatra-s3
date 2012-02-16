# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'sinatra-s3/version'

spec = Gem::Specification.new do |s|
  s.name = "sinatra-s3"
  s.version = ::S3::VERSION
  s.author = "David Ricciardi"
  s.email = "nricciar@gmail.com"
  s.homepage = "http://github.com/nricciar/sinatra-s3"
  s.platform = Gem::Platform::RUBY
  s.summary = "An implementation of the Amazon S3 API in Ruby"
  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_path = "lib"
  s.description = File.read("README")
  s.executables = ['sinatra-s3']
  s.has_rdoc = false
  s.extra_rdoc_files = ["README"]
  s.add_dependency("sinatra", ">= 1.0")
  s.add_dependency("builder")
  s.add_dependency("haml", ">= 2.2.15")
end
