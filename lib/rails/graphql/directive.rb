# frozen_string_literal: true

module Rails
  module GraphQL
    # = GraphQL Directive
    #
    # This is the base object for directives definition.
    # See: http://spec.graphql.org/June2018/#DirectiveDefinition
    #
    # Whenever you want to use a directive, you can use the ClassName(...)
    # shortcut (which is the same as ClassName.new(...)).
    #
    # Directives works as event listener and trigger, which means that some
    # actions will trigger directives events, and the directive can listen to
    # these events and perform an action
    #
    # ==== Examples
    #
    #   argument :test, :boolean, directives: FlagDirective()
    #
    #   # On defining an enum value
    #   add :old_value, directives: DeprecatedDirective(reason: 'not used anymore')
    class Directive
      extend ActiveSupport::Autoload
      extend Helpers::InheritedCollection
      extend Helpers::WithEvents
      extend Helpers::WithCallbacks
      extend Helpers::WithArguments
      extend Helpers::WithGlobalID
      extend Helpers::Registerable

      VALID_LOCATIONS = Rails::GraphQL::Type::Enum::DirectiveLocationEnum
        .values.to_a.map { |value| value.downcase.to_sym }.freeze

      EXECUTION_LOCATIONS  = VALID_LOCATIONS[0..6].freeze
      DEFINITION_LOCATIONS = VALID_LOCATIONS[7..17].freeze

      class << self
        def kind
          :directive
        end

        # Return the name of the object as a GraphQL name, ensure to use the
        # first letter as lower case when being auto generated
        def gql_name
          return @gql_name if defined?(@gql_name)
          @gql_name = super.camelize(:lower)
        end

        # Get the list of locations of a the directive
        def locations
          @locations ||= Set.new
        end

        # A secure way to specify the locations of a the directive
        def placed_on(*list)
          validate_locations!(list)
          @locations = (superclass.try(:locations)&.dup || Set.new) \
            unless defined?(@locations)

          @locations.merge(list)
        end

        # This method overrides the locations of a the directive
        def placed_on!(*list)
          validate_locations!(list)
          @locations = list.to_set
        end

        # Ensure to return the directive class
        def gid_base_class
          GraphQL::Directive
        end

        # A helper method that allows directives to be initialized while
        # correctly parsing the arguments
        def build(**xargs)
          xargs = xargs.stringify_keys
          result = all_arguments.each_pair.each_with_object({}) do |(name, argument), hash|
            hash[name] = argument.deserialize(xargs[argument.gql_name] || xargs[name.to_s])
          end

          new(**result)
        end

        # Return the directive, instantiate if it has params
        def find_by_gid(gid)
          options = { namespaces: gid.namespace, base_class: :Directive }
          klass = GraphQL.type_map.fetch!(gid.name, **options)
          gid.instantiate? ? klass.build(**gid.params) : klass
        end

        def eager_load!
          super

          TypeMap.loaded! :Directive
        end

        def inspect
          return '#<GraphQL::Directive>' if eql?(GraphQL::Directive)

          args = arguments.each_value.map(&:inspect)
          args = args.presence && "(#{args.join(', ')})"
          "#<GraphQL::Directive @#{gql_name}#{args}>"
        end

        private

          # Check if the given list the locations are valid
          def validate_locations!(list)
            list.flatten!
            list.map! { |item| item.to_s.underscore.to_sym }

            invalid = list - VALID_LOCATIONS
            raise ArgumentError, <<~MSG.squish unless invalid.empty?
              Invalid locations for @#{gql_name}: #{invalid.to_sentence}.
            MSG
          end

          # Provide a nice way to use a directive without calling
          # +Directive.new+, like the +DeprecatedDirective+ can be initialized
          # using +GraphQL::DeprecatedDirective(*args)+
          def inherited(subclass)
            subclass.abstract = false
            super if defined? super

            return if subclass.anonymous?
            method_name = subclass.name.demodulize
            subclass.module_parent.define_singleton_method(method_name) do |*args, &block|
              subclass.new(*args, &block)
            end
          end

          # Allows checking value existence
          def respond_to_missing?(method_name, *)
            (const_defined?(method_name) rescue nil) || autoload?(method_name) || super
          end

          # Allow fast creation of values
          def method_missing(method_name, *args, **xargs, &block)
            const_get(method_name)&.new(*args, **xargs, &block) || super
          rescue ::NameError
            super
          end
      end

      self.abstract = true

      eager_autoload do
        autoload :DeprecatedDirective
        autoload :IncludeDirective
        autoload :SkipDirective
      end

      delegate :locations, :gql_name, :gid_base_class, to: :class

      array_sanitizer = ->(setting) do
        Array.wrap(setting)
      end

      object_sanitizer = ->(setting) do
        Array.wrap(setting).map! do |item|
          next item unless item.is_a?(String) || item.is_a?(Symbol)
          GraphQL.type_map.fetch(item, namespaces: namespaces) ||
            ::GraphQL.const_get(item)
        end
      end

      event_filter(:for, object_sanitizer) do |options, event|
        options.any?(&event.source.method(:of_type?))
      end

      event_filter(:on, object_sanitizer) do |options, event|
        event.respond_to?(:on?) && options.any?(&event.method(:on?))
      end

      event_filter(:during, array_sanitizer) do |options, event|
        event.key?(:phase) && options.include?(event[:phase])
      end

      attr_reader :args

      def initialize(args = nil, **xargs)
        @args = args || OpenStruct.new(xargs.transform_keys { |key| key.to_s.underscore })
        @args.freeze
      end

      # Once the directive is correctly prepared, we need to assign the owner
      def assing_owner!(owner)
        raise ArgumentError, <<~MSG.squish if defined?(@owner)
          Owner already assigned for @#{gql_name} directive.
        MSG

        @owner = owner
      end

      # Corretly turn all the arguments into their +as_json+ version and return
      # a hash of them
      def args_as_json
        all_arguments.each_pair.each_with_object({}) do |(name, argument), hash|
          hash[argument.gql_name] = argument.as_json(@args[name])
        end
      end

      # Corretly turn all the arguments into their +to_json+ version and return
      # a hash of them
      def args_to_json
        all_arguments.each_pair.each_with_object({}) do |(name, argument), hash|
          hash[argument.gql_name] = argument.to_json(@args[name])
        end
      end

      # When fetching all the events, embed the actual instance as the context
      # of the callback
      def all_events
        @all_events ||= self.class.all_events.transform_values do |events|
          events.map { |item| Callback.set_context(item, self) }
        end
      end

      # Checks if all the arguments provided to the directive instance are valid
      def validate!(*)
        invalid = all_arguments.reject { |name, arg| arg.valid?(@args[name]) }
        return if invalid.empty?

        invalid = invalid.map { |name, _| <<~MSG.chomp }
          invalid value "#{@args[name].inspect}" for #{name} argument
        MSG

        raise ArgumentError, <<~MSG.squish
          Invalid usage of @#{gql_name} directive: #{invalid.to_sentence}.
        MSG
      end

      def inspect
        args = all_arguments.map do |name, arg|
          "#{arg.gql_name}: #{@args[name].inspect}" unless @args[name].nil?
        end.compact

        args = args.presence && "(#{args.join(', ')})"
        "@#{gql_name}#{args}"
      end

      %i[to_global_id to_gid to_gid_param].each do |method_name|
        define_method(method_name) do
          self.class.public_send(method_name, args_as_json.compact)
        end
      end

    end
  end
end
