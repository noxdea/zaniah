# frozen_string_literal: true

module Zaniah
  module Input
    class FocusHandle
      attr_reader :parent, :children, :context, :owner
      attr_accessor :on_action, :on_focus

      def initialize(parent: nil, context: {}, owner: nil)
        @parent, @context, @owner, @children = parent, context, owner, []
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
