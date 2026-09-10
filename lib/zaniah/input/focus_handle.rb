# frozen_string_literal: true

module Zaniah
  module Input
    class FocusHandle
      attr_reader :parent, :children, :context
      attr_accessor :on_action, :on_focus

      def initialize(parent: nil, context: {})
        @parent, @context, @children = parent, context, []
        parent&.children&.push(self)
      end

      def ancestors
        list, current = [], self
        while current
          list << current
          current = current.parent
        end
        list
      end
    end
  end
end
