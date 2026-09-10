# frozen_string_literal: true

module Zaniah
  module Input
    class Dispatcher
      attr_reader :focused

      def initialize(keymap: Keymap.new)
        @keymap, @hits = keymap, []
      end

      def focus(handle)
        return if @focused == handle
        @focused&.on_focus&.call(false)
        @focused = handle
        handle&.on_focus&.call(true)
      end

      def key(key)
        chain = @focused ? @focused.ancestors : []
        context = chain.reverse.each_with_object({}) { |handle, result| result.merge!(handle.context) }
        action = @keymap.dispatch(key, context: context)
        return action if action.nil? || action == :pending
        chain.each { |handle| break if handle.on_action&.call(action) }
        action
      end

      def clear_hits = @hits.clear

      def hit(bounds, clip: nil, &handler)
        bounds = bounds.intersect(@clip) if @clip
        @hits << [clip ? bounds.intersect(clip) : bounds, handler]
      end

      def clip(bounds)
        previous = @clip
        @clip = previous ? previous.intersect(bounds) : bounds
        yield
      ensure
        @clip = previous
      end

      def mouse(event)
        if @capture
          @capture.call(event)
          @capture = nil if event.is_a?(MouseUp)
          return true
        end
        @hits.reverse_each do |bounds, handler|
          next unless bounds.contains?(event.position)
          handled = handler.call(event)
          @capture = handler if handled == :capture && event.is_a?(MouseDown)
          return true if handled
        end
        false
      end
    end
  end
end
