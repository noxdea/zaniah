# frozen_string_literal: true

module Zaniah
  module UI
    class HoverCard < Component
      def initialize(content, anchor:, open_delay: 0.5, close_delay: 0.2)
        super()
        raise ArgumentError, "delays must be nonnegative" if open_delay.negative? || close_delay.negative?
        raise ArgumentError, "anchor must be an element, component, Point, or Bounds" unless
          anchor.respond_to?(:request_layout) || anchor.is_a?(Point) || anchor.is_a?(Bounds)
        @content, @anchor = content, anchor
        @open_delay, @close_delay = Float(open_delay), Float(close_delay)
        @open = false
      end

      def open? = @open
      def open(value = true)
        @open = !!value
        @open_at = @close_at = nil
        @cx&.window&.request_frame
        self
      end
      def close = open(false)

      def build(cx)
        @cx = cx
        update_visibility(cx)
        root = Div.new
        root.child(@anchor) if renderable_anchor?
        return root unless @open

        anchor = anchor_bounds
        box = Placement.place(anchor, Size.new(240, 120), viewport(cx), side: :bottom)
        @card_box = box
        panel = Anchored.new(anchor: Point.new(box.x, box.y)).w(box.width).h(box.height)
          .p(cx.theme.spacing[3]).bg(cx.theme.colors.surface).border(1)
          .border_color(cx.theme.colors.border).rounded(cx.theme.radii[:md])
          .style(shadows: cx.theme.shadows[:md], z_index: Scene::LAYER_POPUP)
          .on_mouse_down { true }.child(@content)
        root.child(panel)
      end

      def prepaint(bounds, state, cx)
        super
        @anchor_box = @anchor.layout_node.bounds if renderable_anchor? && @anchor.layout_node
      end

      def tui_cells(*) = @open ? (@content.respond_to?(:tui_cells) ? @content.tui_cells.to_s : "hover card") : ""

      def accessibility_node(cx)
        return @anchor.accessibility_node(cx) if !@open && renderable_anchor? && @anchor.respond_to?(:accessibility_node)
        return unless @open
        child = @content.accessibility_node(cx) if @content.respond_to?(:accessibility_node)
        node(:dialog, states: {modal: false}, children: [child].compact)
      end

      private

      def renderable_anchor? = @anchor.respond_to?(:request_layout)
      def anchor_bounds
        return @anchor_box || Bounds.new(0, 0, 0, 0) if renderable_anchor?
        return Bounds.new(@anchor.x, @anchor.y, 0, 0) if @anchor.is_a?(Point)
        @anchor
      end

      def viewport(cx) = Bounds.new(0, 0, cx.window.content_size.width, cx.window.content_size.height)

      def update_visibility(cx)
        pointer = cx.window.pointer_position
        focused = cx.dispatcher.focused&.owner
        active = descendant?(focused, @anchor) || descendant?(focused, @content) ||
          !!(pointer && ((anchor_bounds&.contains?(pointer)) || (@open && @card_box&.contains?(pointer))))
        now = cx.window.clock.call
        if active
          @close_at = nil
          @open_at ||= now + @open_delay unless @open
          @open = true if @open_at && now >= @open_at
        else
          @open_at = nil
          @close_at ||= now + @close_delay if @open
          @open = false if @close_at && now >= @close_at
        end
        cx.window.request_frame if (@open_at && !@open) || (@close_at && @open)
      end

      def descendant?(owner, target)
        while owner
          return true if owner.equal?(target)
          owner = owner.respond_to?(:parent) ? owner.parent : nil
        end
        false
      end
    end
  end
end
