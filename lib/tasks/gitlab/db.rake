namespace :gitlab do
  namespace :db do
    desc 'GitLab | Manually insert schema migration version'
    task :mark_migration_complete, [:version] => :environment do |_, args|
      unless args[:version]
        puts "Must specify a migration version as an argument".color(:red)
        exit 1
      end

      version = args[:version].to_i
      if version == 0
        puts "Version '#{args[:version]}' must be a non-zero integer".color(:red)
        exit 1
      end

      sql = "INSERT INTO schema_migrations (version) VALUES (#{version})"
      begin
        ActiveRecord::Base.connection.execute(sql)
        puts "Successfully marked '#{version}' as complete".color(:green)
      rescue ActiveRecord::RecordNotUnique
        puts "Migration version '#{version}' is already marked complete".color(:yellow)
      end
    end

    desc 'Drop all tables'
    task :drop_tables => :environment do
      connection = ActiveRecord::Base.connection
      tables = connection.tables
      tables.delete 'schema_migrations'
      # Truncate schema_migrations to ensure migrations re-run
      connection.execute('TRUNCATE schema_migrations')

      # Drop tables with cascade to avoid dependent table errors
      # PG: http://www.postgresql.org/docs/current/static/ddl-depend.html
      # MySQL: http://dev.mysql.com/doc/refman/5.7/en/drop-table.html
      # Add `IF EXISTS` because cascade could have already deleted a table.
      tables.each { |t| connection.execute("DROP TABLE IF EXISTS #{connection.quote_table_name(t)} CASCADE") }
    end

    desc 'Configures the database by running migrate, or by loading the schema and seeding if needed'
    task configure: :environment do
      if ActiveRecord::Base.connection.tables.any?
        Rake::Task['db:migrate'].invoke
      else
        Rake::Task['db:schema:load'].invoke
        Rake::Task['db:seed_fu'].invoke
      end
    end
  end
end
