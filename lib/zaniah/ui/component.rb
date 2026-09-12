# frozen_string_literal: true

module Zaniah
  module UI
    class Component
      include LengthUnits
      extend Variants

      attr_reader :root, :layout_node, :parent

      def initialize
        @component_style = {}
      end

      def build(_cx) = raise NotImplementedError
      def key(value) = (@key = value; self)
      def test_id(value = (getter = true)) = getter ? @test_id : (@test_id = value.to_s.freeze; self)
      def style(**properties) = (@component_style.merge!(properties); self)
      def accessibility_node(_cx) = nil
      def tui_cells(_bounds = nil, _cx = nil) = nil
      def focus_handle = @root&.focus_handle
      def children = @root&.respond_to?(:children) ? @root.children : []

      {w: :width, h: :height, min_w: :min_width, min_h: :min_height,
       max_w: :max_width, max_h: :max_height, p: :padding, m: :margin,
       gap: :gap, border: :border}.each do |method, property|
        define_method(method) { |value| style(**{property => value}) }
      end

      def flex_1 = style(flex_grow: 1, flex_basis: 0)
      def w_full = style(width: percent(100))
      def h_full = style(height: percent(100))

      def request_layout(cx)
        previous_focus = focus_handle
        @restore_focus = previous_focus && cx.dispatcher.focused.equal?(previous_focus)
        @restore_origin = cx.dispatcher.focus_origin if @restore_focus
        @root = build(cx)
        unless @root.respond_to?(:request_layout) && @root.respond_to?(:prepaint) && @root.respond_to?(:paint)
          raise TypeError, "component build must return a renderable element"
        end
        @root.key(@key) if @key && @root.respond_to?(:key)
        @root.test_id(@test_id) if @test_id && @root.respond_to?(:test_id)
        @root.style(**@component_style) if !@component_style.empty? && @root.respond_to?(:style)
        @root.send(:parent=, self) if @root.respond_to?(:parent=, true)
        @layout_node = @root.request_layout(cx)
      end

      def prepaint(bounds, state, cx)
        @bounds = bounds
        @root.prepaint(bounds, state, cx)
        if @restore_focus && (handle = focus_handle)
          cx.dispatcher.focus(handle, origin: @restore_origin)
          @restore_focus = false
        end
      end
      def paint(bounds, state, prepaint, cx) = @root.paint(bounds, state, prepaint, cx)

      protected

      attr_writer :parent

      private

      def node(role, label: nil, value: nil, states: {}, children: [], actions: [])
        Accessibility.node(role: role, label: label, value: value,
          bounds: @layout_node&.bounds, states: states, children: children, actions: actions)
      end
    end
  end
end
