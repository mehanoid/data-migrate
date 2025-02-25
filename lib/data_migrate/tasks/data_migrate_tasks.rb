module DataMigrate
  module Tasks
    module DataMigrateTasks
      extend self

      def schema_migrations_path
        File.join('db', 'migrate')
      end

      def migrations_paths
        @migrations_paths ||= DataMigrate.config.data_migrations_path
      end

      def dump
        if dump_schema_after_migration?
          filename = DataMigrate::DatabaseTasks.schema_file
          ActiveRecord::Base.establish_connection(DataMigrate.config.db_configuration) if DataMigrate.config.db_configuration
          File.open(filename, "w:utf-8") do |file|
            DataMigrate::SchemaDumper.dump(ActiveRecord::Base.connection, file)
          end
        end
      end

      def migrate
        target_version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil

        DataMigrate::DataMigrator.assure_data_schema_table
        DataMigrate::MigrationContext.new(migrations_paths).migrate(target_version)
      end

      def abort_if_pending_migrations(migrations, message)
        if migrations.any?
          puts "You have #{migrations.size} pending #{migrations.size > 1 ? 'migrations:' : 'migration:'}"
          migrations.each do |pending_migration|
            puts "  %4d %s" % [pending_migration[:version], pending_migration[:name]]
          end
          abort message
        end
      end

      def dump_schema_after_migration?
        if ActiveRecord.respond_to?(:dump_schema_after_migration)
          ActiveRecord.dump_schema_after_migration
        else
          ActiveRecord::Base.dump_schema_after_migration
        end
      end

      def status
        config = connect_to_database
        return unless config

        connection = ActiveRecord::Base.connection
        puts "\ndatabase: #{config['database']}\n\n"
        DataMigrate::StatusService.dump(connection)
      end

      def status_with_schema
        config = connect_to_database
        return unless config

        db_list_data = ActiveRecord::Base.connection.select_values(
          "SELECT version FROM #{DataMigrate::DataSchemaMigration.table_name}"
        )
        db_list_schema = ActiveRecord::Base.connection.select_values(
          "SELECT version FROM #{ActiveRecord::SchemaMigration.schema_migrations_table_name}"
        )
        file_list = []

        Dir.foreach(File.join(Rails.root, migrations_paths)) do |file|
          # only files matching "20091231235959_some_name.rb" pattern
          if match_data = /(\d{14})_(.+)\.rb/.match(file)
            status = db_list_data.delete(match_data[1]) ? 'up' : 'down'
            file_list << [status, match_data[1], match_data[2], 'data']
          end
        end

        Dir.foreach(File.join(Rails.root, schema_migrations_path)) do |file|
          # only files matching "20091231235959_some_name.rb" pattern
          if match_data = /(\d{14})_(.+)\.rb/.match(file)
            status = db_list_schema.delete(match_data[1]) ? 'up' : 'down'
            file_list << [status, match_data[1], match_data[2], 'schema']
          end
        end

        file_list.sort!{|a,b| "#{a[1]}_#{a[3] == 'data' ? 1 : 0}" <=> "#{b[1]}_#{b[3] == 'data' ? 1 : 0}" }

        # output
        puts "\ndatabase: #{config['database']}\n\n"
        puts "#{"Status".center(8)} #{"Type".center(8)}  #{"Migration ID".ljust(14)} Migration Name"
        puts "-" * 60
        file_list.each do |file|
          puts "#{file[0].center(8)} #{file[3].center(8)} #{file[1].ljust(14)}  #{file[2].humanize}"
        end
        db_list_schema.each do |version|
          puts "#{'up'.center(8)}  #{version.ljust(14)}  *** NO SCHEMA FILE ***"
        end
        db_list_data.each do |version|
          puts "#{'up'.center(8)}  #{version.ljust(14)}  *** NO DATA FILE ***"
        end
        puts
      end

      private

      def connect_to_database
        config = if ActiveRecord.version < Gem::Version.new('6.1')
          ActiveRecord::Base.configurations[Rails.env || 'development']
        else
          ActiveRecord::Base.configurations.find_db_config(Rails.env || 'development').configuration_hash
        end
        ActiveRecord::Base.establish_connection(config)

        unless DataMigrate::DataSchemaMigration.table_exists?
          puts 'Data migrations table does not exist yet.'
          config = nil
        end
        unless ActiveRecord::SchemaMigration.table_exists?
          puts 'Schema migrations table does not exist yet.'
          config = nil
        end
        config
      end
    end
  end
end
