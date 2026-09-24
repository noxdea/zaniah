# frozen_string_literal: true

module Zaniah
  module UI
    class ZoomPanView < Component
      attr_reader :zoom

      def initialize(content, zoom: 1, min_zoom: 0.1, max_zoom: 8)
        super()
        @content = content
        @zoom, @min_zoom, @max_zoom = Float(zoom), Float(min_zoom), Float(max_zoom)
        raise ArgumentError, "zoom range must be finite and positive" unless [@zoom, @min_zoom, @max_zoom].all? { |value| value.finite? && value.positive? } && @min_zoom <= @zoom && @zoom <= @max_zoom
        @pan = Point.new(0, 0)
      end

      def build(cx)
        @cx = cx
        @layer = Div.new.style(position: :absolute, left: 0, top: 0).child(@content)
        Div.new.w_full.h_full.overflow_hidden
          .focusable(context: {in_zoom_pan: true}) { |action| zoom_action(action) }
          .on_scroll_wheel { |event, _context| scroll(event) }
          .on_magnify { |event, _context| zoom_at(@zoom * (1 + event.delta), event.position) }
          .on_mouse_down { |event, _context| @last_pan = event.position if event.button == :left }
          .on_drag { |event, _context| drag(event) }
          .on_mouse_up { |_event, _context| @last_pan = nil }
          .child(@layer)
      end

      def prepaint(bounds, state, cx)
        @bounds = bounds
        @layer.style(transform: Transform.new(@zoom, 0, 0, @zoom,
          bounds.x * (1 - @zoom) + @pan.x, bounds.y * (1 - @zoom) + @pan.y))
        super
      end

      def fit
        bounds = @content.layout_node&.bounds
        bounds && zoom_to(Bounds.new(0, 0, bounds.width, bounds.height))
      end

      def zoom_to(rect)
        raise ArgumentError, "zoom target must be a nonempty Bounds" unless rect.is_a?(Bounds) && [rect.x, rect.y, rect.width, rect.height].all? { |n| n.is_a?(Numeric) && n.finite? } && rect.width.positive? && rect.height.positive?
        return false unless @bounds
        @zoom = [@bounds.width.to_f / rect.width, @bounds.height.to_f / rect.height].min.clamp(@min_zoom, @max_zoom)
        @pan = Point.new((@bounds.width - rect.width * @zoom) / 2 - rect.x * @zoom,
          (@bounds.height - rect.height * @zoom) / 2 - rect.y * @zoom)
        @cx&.window&.request_frame
        true
      end

      def view_to_content(point)
        raise ArgumentError, "point must be a Point" unless point.is_a?(Point)
        return nil unless @bounds
        Point.new((point.x - @bounds.x - @pan.x) / @zoom,
          (point.y - @bounds.y - @pan.y) / @zoom)
      end

      def tui_cells(*) = "#{(@zoom * 100).round}% #{@content.respond_to?(:tui_cells) ? @content.tui_cells : @content.respond_to?(:text) ? @content.text : "content"}"
      def accessibility_node(cx) = node(:group, value: @zoom, states: {zoom: @zoom}, actions: %i[zoom_in zoom_out zoom_reset],
        children: [@content.respond_to?(:accessibility_node) ? @content.accessibility_node(cx) : nil].compact)
      def accessibility_action(_item, action) = zoom_action(action)

      private

      def zoom_action(action)
        return false unless @bounds
        center = Point.new(@bounds.x + @bounds.width / 2, @bounds.y + @bounds.height / 2)
        case action
        when :zoom_in then zoom_at(@zoom * 1.25, center)
        when :zoom_out then zoom_at(@zoom / 1.25, center)
        when :zoom_reset
          @zoom, @pan = 1.0.clamp(@min_zoom, @max_zoom), Point.new(0, 0)
          @cx&.window&.request_frame
          true
        else false
        end
      end

      def scroll(event)
        return false unless event.modifiers.include?("ctrl")
        zoom_at(@zoom * Math.exp(-event.delta.y / 1200.0), event.position)
      end

      def zoom_at(value, anchor)
        return false unless @bounds && value.finite? && value.positive?
        next_zoom = value.clamp(@min_zoom, @max_zoom)
        return false if next_zoom == @zoom
        content = view_to_content(anchor)
        @zoom = next_zoom
        @pan = Point.new(anchor.x - @bounds.x - content.x * @zoom,
          anchor.y - @bounds.y - content.y * @zoom)
        @cx&.window&.request_frame
        true
      end

      def drag(event)
        return false unless @last_pan
        @pan = Point.new(@pan.x + event.position.x - @last_pan.x,
          @pan.y + event.position.y - @last_pan.y)
        @last_pan = event.position
        @cx&.window&.request_frame
        true
      end
    end
  end
end
