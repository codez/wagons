
namespace :wagon do
  desc "Run wagon migrations (options: VERSION=x, WAGON=abc, VERBOSE=false)"
  task :migrate => [:environment, :'db:load_config'] do
    ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
    wagons.each do |wagon|
      wagon.migrate(ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
    end
  end
  
  desc "Revert wagon migrations (options: WAGON=abc, VERBOSE=false)"
  task :revert => [:environment, :'db:load_config'] do
    ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
    wagons.reverse.each do |wagon|
      wagon.revert
    end
  end
  
  desc "Seed wagon data (options: WAGON=abc)"
  task :seed => :abort_if_pending_migrations do 
    wagons.each { |wagon| wagon.load_seed }
  end
  
  desc "Unseed wagon data (options: WAGON=abc)"
  task :unseed => :abort_if_pending_migrations do
    wagons.reverse.each { |wagon| wagon.unload_seed }
  end
  
  desc "Migrate and seed wagons"
  task :setup => [:migrate, :seed]
  
  desc "Remove the specified wagon"
  task :remove do
    if wagons.size != 1
      puts "Please specify a WAGON to remove"
    elsif message = wagons.first.protect?
      puts message
    else
      Rake::Task['wagon:unseed'].invoke
      Rake::Task['wagon:revert'].invoke
    end
  end
  
  desc "Creates a Wagonfile for development"
  task :file do
    file = Rails.root.join('Wagonfile')
    unless File.exist?(file)
      File.open(file, 'w') do |f|
        f.puts <<FIN
group :development do
    # Load all wagons found in vendor/wagons/*
    Dir[File.expand_path('../vendor/wagons/**/*.gemspec', __FILE__)].each do |spec|
        gem File.basename(spec, '.gemspec'), :path => File.expand_path('..', spec)
    end
end
FIN
      end
    end
    gemfile = Rails.root.join('Gemfile')
    content = File.read(gemfile)
    unless content =~ /wagonfile/
      File.open(gemfile, 'w') do |f|
        f.puts content
        f.puts "\n\n"
        f.puts "# Include the wagon gems you want attached in Wagonfile. 
# Do not check Wagonfile into source control.
#
# To create a Wagonfile suitable for development, run 'rake wagon:file'
wagonfile = File.expand_path('../Wagonfile', __FILE__)
eval(File.read(wagonfile)) if File.exist?(wagonfile)"
      end
    end
  end
  
  desc "list the loaded wagons"
  task :list => :environment do  # depend on environment to get correct order
    wagons.each {|p| puts p.wagon_name }
  end
  
  namespace :test do
    desc "Create script to test all wagons at once"
    task :script => :environment do
      script = 'vendor/wagons/test_wagons.sh'
      File.open(script, 'w') do |f|
        wagons.each do |w|
          f.puts "(echo && echo '*** TESTING #{w.wagon_name.upcase} ***' && cd #{w.root.to_s[(Rails.root.to_s.size+1)..-1]} && bundle exec rake)"
        end
      end
    end
  end
  
  # desc "Raises an error if there are pending wagon migrations"
  task :abort_if_pending_migrations => :environment do
    pending_migrations = ActiveRecord::Migrator.new(:up, wagons.collect(&:migrations_paths).flatten).pending_migrations

    if pending_migrations.any?
      puts "You have #{pending_migrations.size} pending migrations:"
      pending_migrations.each do |pending_migration|
        puts '  %4d %s' % [pending_migration.version, pending_migration.name]
      end
      abort %{Run `rake wagon:migrate` to update your database then try again.}
    end
  end
end

# Load the wagons specified by WAGON or all available.
def wagons
  to_load = ENV['WAGON'].blank? ? :all : ENV['WAGON'].split(",").map(&:strip)
  wagons = Wagon.all.select { |wagon| to_load == :all || to_load.include?(wagon.wagon_name) }
  puts "Please specify at least one valid WAGON" if wagons.blank?
  wagons
end
