$:.unshift "./lib"
require 'rake'
require 'rake/testtask'
require 'rake/gempackagetask'
require 'sinatra-s3'
require 'sinatra-s3/tasks'

spec = Gem::Specification.new do |s| 
  s.name = "sinatra-s3"
  s.version = S3::VERSION
  s.author = "David Ricciardi"
  s.email = "nricciar@gmail.com"
  s.homepage = "http://github.com/nricciar/sinatra-s3"
  s.platform = Gem::Platform::RUBY
  s.summary = "An implementation of the Amazon S3 API in Ruby"
  s.files = FileList["{bin,lib,public,examples}/**/*"].to_a +
    FileList["db/migrate/*"].to_a +
    ["Rakefile","s3.yml.example"]
  s.require_path = "lib"
  s.executables = ['sinatra-s3']
  s.test_files = FileList["{test}/*.rb"].to_a
  s.has_rdoc = false
  s.extra_rdoc_files = ["README"]
  s.add_dependency("sinatra", ">= 1.0")
  s.add_dependency("aws-s3", ">= 0.6.2")
  s.add_dependency("haml", ">= 2.2.15")
end

Rake::GemPackageTask.new(spec) do |pkg| 
  pkg.need_tar = true 
end 

namespace :test do
  find_file = lambda do |name|
    file_name = lambda {|path| File.join(path, "#{name}.rb")}
    root = $:.detect do |path|
      File.exist?(file_name[path])
    end
    file_name[root] if root
  end

  TEST_LOADER = find_file['rake/rake_test_loader']
  multiruby = lambda do |glob|
    system 'multiruby', TEST_LOADER, *Dir.glob(glob)
  end

  Rake::TestTask.new(:all) do |test|
    test.pattern = 'test/**/*_test.rb'
    test.verbose = true
  end
end
