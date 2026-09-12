# frozen_string_literal: true

module Zaniah
  module UI
    class Scrollbar < Element
      def initialize(scroll_state, axis: :vertical, mode: :overlay)
        super()
        raise ArgumentError, "axis must be vertical or horizontal" unless %i[vertical horizontal].include?(axis)
        raise ArgumentError, "mode must be overlay, always, or hidden" unless %i[overlay always hidden].include?(mode)
        @scroll_state, @axis, @mode = scroll_state, axis, mode
        style(**(axis == :vertical ? {width: 8} : {height: 8}), display: mode == :hidden ? :none : :flex)
        on_mouse_down { |event, cx| start_drag(event, cx) }
        on_drag { |event, cx| drag(event, cx) }
        on_mouse_up { @drag_offset = nil }
        focusable(context: {in_slider: true}) { |action| keyboard_scroll(action) }
      end

      def prepaint(bounds, state, cx)
        @bounds, @cx = bounds, cx
        super
      end

      def paint(bounds, _state, _prepaint, cx)
        return if maximum.zero?
        flags = cx.interactivity.for(self)
        animation_key = [:scrollbar, object_id]
        active = flags.include?(:hover) || @drag_offset
        if @mode == :always || active
          cx.animator.animate(animation_key, from: cx.animator.value(animation_key, 0.0), to: 1.0,
            duration: cx.theme.motion.duration_fast, easing: :ease_out) unless cx.animator.value(animation_key, 0.0) == 1.0
        elsif @last_revision != @scroll_state.revision
          cx.animator.animate(animation_key, from: 1.0, to: 0.0,
            duration: cx.theme.motion.duration_slow, easing: :ease_in)
        end
        @last_revision = @scroll_state.revision
        opacity = @mode == :always ? 1.0 : cx.animator.value(animation_key, 0.0)
        start, length = thumb(bounds)
        cx.scene.push_opacity(opacity) do
          cx.scene.quad(bounds.x, bounds.y, bounds.width, bounds.height, color: "#0003", radius: 4)
          x, y, width, height = @axis == :vertical ? [bounds.x, start, bounds.width, length] : [start, bounds.y, length, bounds.height]
          cx.scene.quad(x, y, width, height, color: "#8997aa", radius: 4)
        end
      end

      def accessibility_node(_cx)
        Accessibility.node(role: :scrollbar, label: "#{@axis.to_s.capitalize} scrollbar", value: offset,
          bounds: @bounds, states: {minimum: 0, maximum: maximum, viewport: viewport}, actions: %i[increment decrement])
      end

      private

      def start_drag(event, cx)
        start, length = thumb(@bounds)
        position = coordinate(event.position)
        if position.between?(start, start + length)
          @drag_offset = position - start
        else
          @scroll_state.scroll_by(position < start ? -viewport : viewport)
          @drag_offset = length / 2.0
          cx.window.request_frame
        end
      end

      def drag(event, cx)
        track = dimension(@bounds)
        length = thumb(@bounds).last
        position = (coordinate(event.position) - coordinate(@bounds) - @drag_offset).clamp(0, track - length)
        @scroll_state.scroll_to(maximum * position / [track - length, 1].max)
        cx.window.request_frame
      end

      def keyboard_scroll(action)
        value = case action
        when :minimum then 0
        when :maximum then maximum
        when :increment then offset + viewport / 10.0
        when :decrement then offset - viewport / 10.0
        when :increment_page then offset + viewport
        when :decrement_page then offset - viewport
        else return false
        end
        @scroll_state.scroll_to(value)
        @cx&.window&.request_frame
        true
      end

      def thumb(bounds)
        track = dimension(bounds)
        content = @axis == :vertical ? @scroll_state.content_size.height : @scroll_state.content_size.width
        length = [track * viewport / [content, 1].max, 20].max.clamp(0, track)
        start = coordinate(bounds) + (track - length) * offset / [maximum, 1].max
        [start, length]
      end

      def coordinate(value) = @axis == :vertical ? value.y : value.x
      def dimension(bounds) = @axis == :vertical ? bounds.height : bounds.width
      def offset = @axis == :vertical ? @scroll_state.offset.y : @scroll_state.offset.x
      def maximum = @axis == :vertical ? @scroll_state.max_offset.y : @scroll_state.max_offset.x
      def viewport = @axis == :vertical ? @scroll_state.viewport_size.height : @scroll_state.viewport_size.width
    end
  end
end
