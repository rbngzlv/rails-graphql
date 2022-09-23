module Rails
  module GraphQL
    module Helpers
      # A inherited collection of arrays that can be unique when it is a set
      class InheritedCollection::Array < InheritedCollection::Base
        # Provide similar functionality of any? but returns the object instead
        def find(value = nil, &block)
          block ||= !value.is_a?(Module) ? value.method(:==) : ->(val) { val.class <= value }
          reverse_each { |item| return item if block.call(item) }
        end

        # Check if a given +value+ is included in any of the definitions
        def include?(value)
          each_definition.any? { |definition| definition.include?(value) }
        end

        # The normal each is the reverse each of the definitions
        def each(&block)
          lazy.reverse_each(&block)
        end

        # The reverse each is the normal each of the definitions
        def reverse_each(&block)
          block.nil? ? lazy : lazy.each(&block)
        end

        # Overrides the lazy operator
        def lazy
          (@type == :set) ? super.uniq : super
        end
      end
    end
  end
end
