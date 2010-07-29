$:.unshift "./lib"
require 'rake'
require 'rake/testtask'
require 'rake/gempackagetask'
require 'sinatra-s3'

spec = Gem::Specification.new do |s| 
  s.name = "sinatra-s3"
  s.version = S3::VERSION
  s.author = "David Ricciardi"
  s.email = "nricciar@gmail.com"
  s.homepage = "http://github.com/nricciar/sinatra-s3"
  s.platform = Gem::Platform::RUBY
  s.summary = "An implementation of the Amazon S3 API in Ruby"
  s.files = FileList["{bin,lib,public}/**/*"].to_a +
    FileList["db/migrate/*"].to_a +
    ["Rakefile"]
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

namespace :setup do
  task :wiki do
    begin
      Bucket.find_root('wiki')
    rescue S3::NoSuchBucket
      wiki_owner = User.find_by_login('wiki')
      if wiki_owner.nil?
	class S3KeyGen
	  include S3::Helpers
	  def secret() generate_secret(); end;
	  def key() generate_key(); end;
	end
	puts "** No wiki user found, creating the `wiki' user."
	wiki_owner = User.create :login => "wiki", :password => S3::DEFAULT_PASSWORD,
	  :email => "wiki@parkplace.net", :key => S3KeyGen.new.key(), :secret => S3KeyGen.new.secret(),
	  :activated_at => Time.now
      end
      wiki_bucket = Bucket.create(:name => 'wiki', :owner_id => wiki_owner.id, :access => 438)
      templates_bucket = Bucket.create(:name => 'templates', :owner_id => wiki_owner.id, :access => 438)
      if defined?(Git)
	wiki_bucket.git_init
	templates_bucket.git_init
      else
	puts "Git support not found therefore Wiki history is disabled."
      end
    end
  end
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
      User.create :login => "admin", :password => S3::DEFAULT_PASSWORD,
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
