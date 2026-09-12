# frozen_string_literal: true

module Zaniah
  module Input
    Hit = Data.define(:bounds, :owner)

    class Dispatcher
      attr_reader :focused, :focus_origin, :focus_tree

      def initialize(keymap: Keymap.default_ui)
        @keymap, @hits = keymap, []
        @transforms = [Transform.identity]
        @focus_tree = FocusTree.new
      end

      def focus(handle, origin: :programmatic)
        return unless handle.nil? || handle.focusable
        @focus_tree.register(handle) if handle
        if @focused == handle
          @focus_origin = origin
          return
        end
        @focused&.on_focus&.call(false)
        @focused, @focus_origin = handle, origin
        handle&.on_focus&.call(true)
        reveal(handle)
      end

      def focus_visible? = @focus_origin == :keyboard

      def key(key)
        chain = @focused ? @focused.ancestors : []
        context = chain.reverse.each_with_object({}) { |handle, result| result.merge!(handle.context) }
        action = @keymap.dispatch(key, context: context)
        return action if action.nil? || action == :pending
        target = case action
        when :focus_next then @focus_tree.next(@focused)
        when :focus_previous then @focus_tree.previous(@focused)
        when :focus_left then @focus_tree.spatial(@focused, :left)
        when :focus_right then @focus_tree.spatial(@focused, :right)
        when :focus_up then @focus_tree.spatial(@focused, :up)
        when :focus_down then @focus_tree.spatial(@focused, :down)
        end
        if target
          focus(target, origin: :keyboard)
          return action
        end
        chain.each { |handle| break if handle.on_action&.call(action) }
        action
      end

      def register_focus(handle)
        owner = handle.owner&.respond_to?(:parent) ? handle.owner.parent : nil
        while owner
          if owner.respond_to?(:focus_handle) && (parent = owner.focus_handle)
            unless parent.equal?(handle)
              handle.parent = parent
              break
            end
          end
          owner = owner.respond_to?(:parent) ? owner.parent : nil
        end
        @focus_tree.register(handle)
      end

      def input(event)
        return false unless @focused
        @focused.ancestors.each { |handle| return true if handle.on_input&.call(event) }
        false
      end

      def clear_hits
        @hits.clear
        @focus_tree.clear
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

      def reveal(handle)
        owner, bounds = handle&.owner, handle&.bounds
        while owner
          owner.scroll_to(bounds, align: :nearest) if bounds && owner.is_a?(ScrollView)
          owner = owner.respond_to?(:parent) ? owner.parent : nil
        end
      end
    end
  end
end
