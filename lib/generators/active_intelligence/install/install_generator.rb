require 'rails/generators'
require 'rails/generators/migration'

module ActiveIntelligence
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc "Creates ActiveIntelligence initializer and migrations"

      def self.next_migration_number(path)
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/active_intelligence.rb"
      end

      def create_migrations
        migration_template "create_conversations_migration.rb.erb",
                          "db/migrate/create_active_intelligence_conversations.rb"

        # Sleep to ensure different timestamps
        sleep 1

        migration_template "create_messages_migration.rb.erb",
                          "db/migrate/create_active_intelligence_messages.rb"
      end

      def create_concern
        template "conversation_manageable.rb", "app/controllers/concerns/active_intelligence/conversation_manageable.rb"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
