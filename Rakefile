require 'rake'
require 'rake/testtask'

namespace :db do
  task :environment do
    require 'active_record'
    require File.join(File.dirname(__FILE__), 's3')
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
      User.create :login => "admin", :password => DEFAULT_PASSWORD,
	:email => "admin@parkplace.net", :key => "44CF9590006BF252F707", :secret => DEFAULT_SECRET,
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
