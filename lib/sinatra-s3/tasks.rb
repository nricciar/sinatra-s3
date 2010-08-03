require 'rake'
require 'rake/testtask'
require 'rake/gempackagetask'
require File.join(File.dirname(__FILE__), 's3')

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

  desc "Setup Wiki"
  task(:setup_wiki => :migrate) do
    begin
      Bucket.find_root('wiki')
      puts "Wiki aready setup."
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
	puts "** Creating the `wiki' and `templates' namespaces."
	wiki_bucket.git_init
	templates_bucket.git_init
      else
	puts "!! Git support not found therefore Wiki history is disabled."
      end
      puts "Wiki setup."
    end
  end
end
