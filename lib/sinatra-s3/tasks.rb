require 'rake'
require 'rake/testtask'
require 'rake/gempackagetask'
require File.join(File.dirname(__FILE__), 's3')
require 'aws-auth/tasks'

namespace :db do
  task :environment do
    ActiveRecord::Base.establish_connection(S3.config[:db])
  end

  desc "Migrate the database"
  task(:migrate => :environment) do
    ActiveRecord::Base.logger = Logger.new(STDOUT)
    ActiveRecord::Migration.verbose = true

    out_dir = File.dirname(S3.config[:db][:database])
    FileUtils.mkdir_p(out_dir) unless File.exists?(out_dir)

    ActiveRecord::Migrator.migrate(File.join(S3::ROOT_DIR, 'db', 'migrate'), ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
  end
end
