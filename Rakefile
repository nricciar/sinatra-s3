$:.unshift "./lib"
require 'rake'
require 'rake/testtask'
require 'rake/gempackagetask'

spec = Gem::Specification.new do |s| 
  s.name = "sinatra-s3"
  s.version = "0.9"
  s.author = "David Ricciardi"
  s.email = "nricciar@gmail.com"
  s.platform = Gem::Platform::RUBY
  s.summary = "An implementation of the Amazon S3 API in Ruby"
  s.files = FileList["{bin,lib,public,db}/**/*"].to_a
  s.require_path = "lib"
  s.autorequire = "name"
  s.test_files = FileList["{test}/*.rb"].to_a
  s.has_rdoc = false
  s.extra_rdoc_files = ["README"]
  s.add_dependency("sinatra", ">= 1.0")
end
 
Rake::GemPackageTask.new(spec) do |pkg| 
  pkg.need_tar = true 
end 

namespace :db do
  task :environment do
    require 'active_record'
    require 's3'
    ActiveRecord::Base.establish_connection(S3.config[:db])
  end

  desc "Migrate the database"
  task(:migrate => :environment) do
    ActiveRecord::Base.logger = Logger.new(STDOUT)
    ActiveRecord::Migration.verbose = true
    ActiveRecord::Migrator.migrate("db/migrate")
    num_users = User.count || 0
    if num_users == 0
      puts "** No users found, creating the `admin' user."
      class S3KeyGen
        include S3::Helpers
        def secret() generate_secret(); end;
        def key() generate_key(); end;
      end
      User.create :login => "admin", :password => DEFAULT_PASSWORD,
	:email => "admin@parkplace.net", :key => S3KeyGen.new.key(), :secret => S3KeyGen.new.secret(),
	:activated_at => Time.now, :superuser => 1
    end
  end
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
