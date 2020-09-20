# frozen_string_literal: true

module Rails # :nodoc:
  module GraphQL # :nodoc:
    # = Rails GraphQL Railtie
    class Railtie < Rails::Railtie # :nodoc:
      config.graphql = GraphQL.config

      rake_tasks do
        load 'rails/graphql.rake'
      end

      runner do
        require_relative './schema'
      end

      # Ensure a valid logger
      initializer 'graphql.logger' do
        ActiveSupport.on_load(:graphql) do
          return if config.logger.present?
          if ::Rails.logger.respond_to?(:tagged)
            config.logger = ::Rails.logger
          else
            config.logger = ActiveSupport::TaggedLogging.new(::Rails.logger)
          end
        end
      end

      # Expose database runtime to controller for logging.
      initializer 'graphql.log_runtime' do
        require_relative './railties/controller_runtime'
        ActiveSupport.on_load(:action_controller) do
          include GraphQL::ControllerRuntime
        end
      end

      # Backtrace cleaner for removing gem paths
      initializer 'graphql.backtrace_cleaner' do
        require_relative './railties/log_subscriber'
        ActiveSupport.on_load(:graphql) do
          GraphQL::LogSubscriber.backtrace_cleaner = ::Rails.backtrace_cleaner
        end
      end

      # Add reloader ability for files under 'app/graphql'
      # TODO: Maybe improve to use rails auto loader
      initializer 'graphql.reloader' do
        ActiveSupport::Reloader.to_prepare do
          Object.send(:remove_const, :GraphQL) if Object.const_defined?(:GraphQL)
          # BUG: Fix problem with reloader and type_map
          # Rails::GraphQL.type_map.clear

          load "#{__dir__}/shortcuts.rb"

          $LOAD_PATH.each do |path|
            next unless path =~ /\/app\/graphql$/
            Dir.glob("#{path}/**/*.rb").each(&method(:load))
          end

          GraphQL::Source.send(:build_pending!)
        end
      end

      # initializer "active_record.set_reloader_hooks" do
      #   ActiveSupport.on_load(:active_record) do
      #     ActiveSupport::Reloader.before_class_unload do
      #       if ActiveRecord::Base.connected?
      #         ActiveRecord::Base.clear_cache!
      #         ActiveRecord::Base.clear_reloadable_connections!
      #       end
      #     end
      #   end
      # end
    end
  end
end
