# frozen_string_literal: true

module Zaniah
  module Input
    class FocusHandle
      attr_reader :parent, :children, :context, :owner
      attr_accessor :on_action, :on_focus, :tab_index, :focusable, :bounds

      def initialize(parent: nil, context: {}, owner: nil, tab_index: nil, focusable: true, bounds: nil)
        @parent, @context, @owner, @children = parent, context, owner, []
        @tab_index, @focusable, @bounds = tab_index, focusable, bounds
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
