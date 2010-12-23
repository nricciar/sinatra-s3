$:.unshift "./lib"
ENV['AWS_AUTH_PATH'] ||= File.expand_path(File.join(File.dirname(__FILE__),'s3.yml'))
require 'rake'
require 'rake/testtask'
require 'rake/gempackagetask'
require 'sinatra-s3'
require 'sinatra-s3/tasks'
require 'bundler'
Bundler::GemHelper.install_tasks

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
