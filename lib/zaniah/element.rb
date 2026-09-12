# frozen_string_literal: true

module Zaniah
  class Element
    include LengthUnits

    attr_reader :layout_node, :parent, :resolved_style

    def initialize
      @style, @children, @handlers = Layout::Style.new, [], {}
      @style_set, @static_flags = StyleSet.new(@style), Set.new
    end

    def child(element)
      if element
        element.send(:parent=, self) if element.respond_to?(:parent=, true)
        @children << element
      end
      self
    end

    def children(elements = nil)
      return @children unless elements
      elements.each { |element| child(element) }
      self
    end

    def style(**properties)
      @style = @style.merge(**properties)
      @style_set.merge(**properties)
      self
    end

    def key(value) = (@key = value; self)
    def test_id(value = (getter = true)) = getter ? @test_id : (@test_id = value.to_s.freeze; self)
    def handlers = @handlers.keys.freeze
    def with_state(&initial) = (@state_initializer = initial; self)
    def bg(color) = style(background: color)
    def border_color(color) = style(border_color: color)
    def rounded(radius) = style(corner_radii: radius)
    def opacity(value) = style(opacity: value)
    def ring(width, color, offset = 0) = style(ring: Ring.new(width, color, offset))
    def tooltip(text) = (@tooltip = text.to_s; self)
    def context_menu(items) = (@context_menu = items; self)
    def flex = style(display: :flex)
    def flex_row = style(flex_direction: :row)
    def flex_col = style(flex_direction: :column)
    def items_center = style(align_items: :center)
    def justify_center = style(justify_content: :center)
    def w_full = style(width: percent(100))
    def h_full = style(height: percent(100))
    def flex_1 = style(flex_grow: 1, flex_basis: 0)
    def overflow_hidden = style(overflow: :hidden)

    %i[hover active focus focus_visible].each do |state|
      define_method(state) { |**properties, &block| state_style(state, properties, &block) }
    end

    %i[disabled selected].each do |state|
      define_method(state) do |value = true, **properties, &block|
        if block || !properties.empty?
          state_style(state, properties, &block)
        else
          value ? @static_flags.add(state) : @static_flags.delete(state)
          self
        end
      end
    end

    {w: :width, h: :height, min_w: :min_width, min_h: :min_height,
     max_w: :max_width, max_h: :max_height, p: :padding, m: :margin,
     gap: :gap, border: :border, border_b: :border_bottom}.each do |method, property|
      define_method(method) { |value| style(**{property => value}) }
    end

    %i[click hover drag scroll_wheel mouse_down mouse_up].each do |kind|
      define_method("on_#{kind}") { |&block| @handlers[kind] = block; self }
    end

    def request_layout(cx)
      @state = cx.state(@key, &@state_initializer) if @key && @state_initializer
      @layout_node = Layout::Node.new(style: @style,
        children: @children.map { |child| child.request_layout(cx) })
    end

    def prepaint(bounds, _state, cx)
      unless @handlers.empty? && !@tooltip && !@context_menu && !@style_set.interactive?
        cx.dispatcher.hit(bounds, owner: self) do |event|
          if event.is_a?(Input::MouseDown) && event.button == :right && @context_menu
            cx.window.context_menu(@context_menu, position: event.position)
            next true
          end
          cx.window.offer_tooltip(@tooltip, position: event.position) if @tooltip && event.is_a?(Input::MouseMove)
          kind = case event
          when Input::MouseDown then @handlers.key?(:mouse_down) ? :mouse_down : :click
          when Input::MouseMove then @dragging && @handlers.key?(:drag) ? :drag : :hover
          when Input::MouseUp then :mouse_up
          when Input::ScrollWheel then :scroll_wheel
          end
          handler = @handlers[kind]
          @dragging = true if event.is_a?(Input::MouseDown) && @handlers[:drag]
          @dragging = false if event.is_a?(Input::MouseUp)
          handler&.call(event, cx)
          @dragging && event.is_a?(Input::MouseDown) ? :capture : !!handler || !!(@tooltip && event.is_a?(Input::MouseMove))
        end
      end
      visit = -> { @children.each { |child| child.prepaint(child.layout_node.bounds, nil, cx) } }
      @style[:overflow] == :visible ? visit.call : cx.dispatcher.clip(bounds, &visit)
    end

    def paint(bounds, _state, _prepaint, cx)
      @resolved_style = @style_set.resolve(cx.interactivity.for(self, @static_flags))
      border = @resolved_style[:border_widths] || @resolved_style[:border]
      border = 0 unless border.is_a?(Numeric)
      background = @resolved_style[:background] || "#0000"
      background = Color.parse(background).opacity(@resolved_style[:opacity]) unless background.is_a?(Gradient)
      cx.scene.quad(bounds.x, bounds.y, bounds.width, bounds.height,
        color: background.is_a?(Gradient) ? "#0000" : background,
        radius: @resolved_style[:corner_radii] || 0, border_width: border,
        border_color: @resolved_style[:border_color] || "#0000")
      paint_children = -> { @children.each { |child| child.paint(child.layout_node.bounds, nil, nil, cx) unless child.layout_node.style[:display] == :none } }
      @style[:overflow] == :visible ? paint_children.call : cx.scene.clip(bounds, &paint_children)
    end

    protected

    attr_writer :parent

    private

    def state_style(state, properties)
      builder = StyleBuilder.new(properties)
      yield(builder) if block_given?
      @style_set.on(state, **builder.properties)
      self
    end
  end
end

require_relative "frame_context"
require_relative "div"
require_relative "text"
require_relative "image"
require_relative "canvas"
require_relative "overlay"
require_relative "anchored"
require_relative "uniform_list"
require_relative "view"
