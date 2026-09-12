# frozen_string_literal: true

module Zaniah
  module Input
    Hit = Data.define(:bounds, :owner)

    class Dispatcher
      attr_reader :focused, :focus_origin

      def initialize(keymap: Keymap.new)
        @keymap, @hits = keymap, []
        @transforms = [Transform.identity]
      end

      def focus(handle, origin: :programmatic)
        if @focused == handle
          @focus_origin = origin
          return
        end
        @focused&.on_focus&.call(false)
        @focused, @focus_origin = handle, origin
        handle&.on_focus&.call(true)
      end

      def focus_visible? = @focus_origin == :keyboard

      def key(key)
        chain = @focused ? @focused.ancestors : []
        context = chain.reverse.each_with_object({}) { |handle, result| result.merge!(handle.context) }
        action = @keymap.dispatch(key, context: context)
        return action if action.nil? || action == :pending
        chain.each { |handle| break if handle.on_action&.call(action) }
        action
      end

      def clear_hits
        @hits.clear
        @transforms.replace([Transform.identity])
      end
      def hits = @hits.map { |bounds, _, owner, _, clip| Hit.new(clip ? bounds.intersect(clip) : bounds, owner) }.freeze

      def hover_chain(position)
        return [] unless position
        owner = @hits.reverse_each.find { |hit| hit_contains?(hit, position) }&.[](2)
        [].tap do |chain|
          while owner
            chain << owner
            owner = owner.respond_to?(:parent) ? owner.parent : nil
          end
        end
      end

      def hit(bounds, clip: nil, owner: nil, transform: @transforms.last, &handler)
        @hits << [bounds, handler, owner, transform, clip || @clip]
      end

      def clip(bounds)
        previous = @clip
        @clip = previous ? previous.intersect(bounds) : bounds
        yield
      ensure
        @clip = previous
      end

      def push_transform(transform)
        raise ArgumentError, "expected a Transform" unless transform.is_a?(Transform)
        @transforms << @transforms.last.compose(transform)
        pushed = true
        yield
      ensure
        @transforms.pop if pushed
      end

      def mouse(event)
        if @capture
          @capture.call(event)
          @capture = nil if event.is_a?(MouseUp)
          return true
        end
        @hits.reverse_each do |hit|
          next unless hit_contains?(hit, event.position)
          handler = hit[1]
          handled = handler.call(event)
          @capture = handler if handled == :capture && event.is_a?(MouseDown)
          return true if handled
        end
        false
      end

      private

      def hit_contains?(hit, position)
        bounds, _, _, transform, clip = hit
        return false if clip && !clip.contains?(position)
        bounds.contains?(transform.inverse.apply(position))
      rescue ArgumentError
        false
      end
    end
  end
end
