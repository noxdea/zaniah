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
    def identity_key = @key
    def paint_style(**properties)
      @paint_opacity = properties.delete(:opacity) if properties.key?(:opacity)
      @paint_style = (@paint_style || {}).merge(properties)
      self
    end
    def transition(*properties, duration:, easing: :ease_in_out)
      raise ArgumentError, "transition needs at least one property" if properties.empty?
      @transition = Transition.new(properties.map(&:to_sym).freeze, Float(duration), easing)
      self
    end
    def test_id(value = (getter = true)) = getter ? @test_id : (@test_id = value.to_s.freeze; self)
    def handlers = @handlers.keys.freeze
    def with_state(&initial) = (@state_initializer = initial; self)
    def bg(color) = style(background: color)
    def border_color(color) = style(border_color: color)
    def rounded(radius) = style(corner_radii: radius)
    def opacity(value) = style(opacity: value)
    def ring(width, color = nil, offset = 0) = style(ring: Ring.new(width, color, offset))
    def cursor(value) = style(cursor: value)
    def focusable(tab_index: 0, context: {}, &on_action)
      @focus_handle ||= Input::FocusHandle.new(owner: self)
      @focus_handle.tab_index, @focus_handle.focusable = Integer(tab_index), true
      @focus_handle.context.merge!(context)
      @focus_handle.on_action = on_action if on_action
      self
    end
    def focus_handle = @focus_handle
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
      transform = @style[:transform] || Transform.identity
      return prepaint_contents(bounds, cx) if transform == Transform.identity
      cx.dispatcher.push_transform(transform) { prepaint_contents(bounds, cx) }
    end

    def paint(bounds, _state, _prepaint, cx)
      flags = cx.interactivity.for(self, @static_flags)
      @resolved_style = transition_style(@style_set.resolve(flags), cx)
      @resolved_style = @resolved_style.merge(**@paint_style) if @paint_style && !@paint_style.empty?
      cx.window.set_cursor(@resolved_style[:cursor]) if flags.include?(:hover) && @resolved_style[:cursor]
      border = @resolved_style[:border_widths] || @resolved_style[:border]
      border = 0 unless border.is_a?(Numeric) || border.is_a?(Edges)
      background = @resolved_style[:background] || "#0000"
      transform = @resolved_style[:transform] || Transform.identity
      z_index = Float(@resolved_style[:z_index])
      operation = lambda do
        if z_index.zero?
          paint_transformed(bounds, border, background, transform, cx)
        else
          cx.scene.layer(Scene::LAYER_CONTENT + z_index) do
            paint_transformed(bounds, border, background, transform, cx)
          end
        end
      end
      @paint_opacity ? cx.scene.push_opacity(@paint_opacity, &operation) : operation.call
      paint_ring(bounds, cx) if @resolved_style[:ring]
    ensure
      @paint_style = nil
      @paint_opacity = nil
    end

    protected

    attr_writer :parent

    private

    def prepaint_contents(bounds, cx)
      if @focus_handle
        @focus_handle.bounds = bounds
        @focus_handle.focusable = !@static_flags.include?(:disabled)
        cx.dispatcher.register_focus(@focus_handle)
      end
      unless @handlers.empty? && !@tooltip && !@context_menu && !@style_set.interactive? && !@focus_handle
        cx.dispatcher.hit(bounds, owner: self) do |event|
          if event.is_a?(Input::MouseDown) && event.button == :right && @context_menu
            cx.window.context_menu(@context_menu, position: event.position)
            next true
          end
          cx.window.offer_tooltip(@tooltip, position: event.position) if @tooltip && event.is_a?(Input::MouseMove)
          cx.dispatcher.focus(@focus_handle, origin: :pointer) if @focus_handle && event.is_a?(Input::MouseDown)
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
          @dragging && event.is_a?(Input::MouseDown) ? :capture : !!handler || !!(@focus_handle && event.is_a?(Input::MouseDown)) || !!(@tooltip && event.is_a?(Input::MouseMove))
        end
      end
      operation = -> { @children.each { |child| child.prepaint(child.layout_node.bounds, nil, cx) } }
      @style[:overflow] == :visible ? operation.call : cx.dispatcher.clip(bounds, &operation)
      prepare_child_animations(cx)
    end

    def paint_transformed(bounds, border, background, transform, cx)
      return paint_contents(bounds, border, background, cx) if transform == Transform.identity
      cx.scene.push_transform(transform) { paint_contents(bounds, border, background, cx) }
    end

    def paint_contents(bounds, border, background, cx)
      shadows = @resolved_style[:shadows]
      shadows = [shadows] if shadows && !shadows.is_a?(Array)
      shadows&.each do |shadow|
        next unless shadow.is_a?(Shadow)
        cx.scene.shadow(bounds.x + shadow.x, bounds.y + shadow.y, bounds.width, bounds.height,
          color: shadow.color, blur: shadow.blur, spread: shadow.spread,
          radius: @resolved_style[:corner_radii] || 0, inset: shadow.inset)
      end
      cx.scene.quad(bounds.x, bounds.y, bounds.width, bounds.height,
        color: background, opacity: @resolved_style[:opacity],
        radius: @resolved_style[:corner_radii] || 0, border_width: border,
        border_color: @resolved_style[:border_color] || "#0000",
        border_style: @resolved_style[:border_style])
      operation = lambda do
        @children.each { |child| child.paint(child.layout_node.bounds, nil, nil, cx) unless child.layout_node.style[:display] == :none }
        @departing_children&.each { |child, old_bounds, opacity| child.paint_style(opacity: opacity).paint(old_bounds, nil, nil, cx) }
      end
      @style[:overflow] == :visible ? operation.call : cx.scene.clip(bounds, &operation)
    end

    def paint_ring(bounds, cx)
      ring = @resolved_style[:ring]
      extent = ring.width + ring.offset
      radius = @resolved_style[:corner_radii] || 0
      radius += extent if radius.is_a?(Numeric)
      cx.scene.layer(Scene::LAYER_FOCUS_RING) do
        paint = -> { cx.scene.quad(bounds.x - extent, bounds.y - extent, bounds.width + extent * 2, bounds.height + extent * 2,
          color: "#0000", radius: radius, border_width: ring.width, border_color: ring.color || cx.theme.colors.ring) }
        transform = @resolved_style[:transform] || Transform.identity
        transform == Transform.identity ? paint.call : cx.scene.push_transform(transform, &paint)
      end
    end

    def state_style(state, properties)
      builder = StyleBuilder.new(properties)
      yield(builder) if block_given?
      @style_set.on(state, **builder.properties)
      self
    end

    def transition_style(target, cx)
      return target unless @transition && @key
      state = cx.state([:transition, @key]) { {targets: {}} }
      values = {}
      @transition.properties.each do |property|
        value = target[property]
        unless state[:targets].key?(property)
          state[:targets][property] = value
          next
        end
        previous = state[:targets][property]
        animation_key = [:transition, @key, property]
        if previous != value
          from = cx.animator.value(animation_key, previous)
          if Animation.interpolatable?(from, value)
            cx.animator.animate(animation_key, from: from, to: value,
              duration: @transition.duration, easing: @transition.easing)
          else
            cx.animator.cancel(animation_key)
          end
          state[:targets][property] = value
        end
        values[property] = cx.animator.value(animation_key, value)
      end
      values.empty? ? target : target.merge(**values)
    end

    def prepare_child_animations(cx)
      keyed = @children.filter_map { |child| [child.identity_key, child] if child.respond_to?(:identity_key) && child.identity_key }
      return if keyed.empty? && !@key && !@child_animation_state
      identity = @key || object_id
      state = cx.state([:children, identity]) { {previous: {}, departing: {}, initialized: false} }
      @child_animation_state = state
      current = keyed.to_h
      duration = cx.theme.motion.duration_base
      keyed.each do |key, child|
        enter_key, move_key = [:enter, identity, key], [:move, identity, key]
        if (departure = state[:departing].delete(key))
          cx.animator.cancel([:exit, identity, key])
          state[:previous][key] = departure.values_at(:child, :bounds)
        end
        previous = state[:previous][key]
        if previous
          old_bounds, new_bounds = previous.last, child.layout_node.bounds
          if old_bounds.x != new_bounds.x || old_bounds.y != new_bounds.y
            cx.animator.animate(move_key, from: 0.0, to: 1.0, duration: duration, easing: :ease_out)
          end
          progress = cx.animator.value(move_key, 1.0)
          if progress < 1
            child.paint_style(transform: Transform.translate((old_bounds.x - new_bounds.x) * (1 - progress), (old_bounds.y - new_bounds.y) * (1 - progress)))
          end
        elsif state[:initialized]
          cx.animator.animate(enter_key, from: 0.0, to: 1.0, duration: duration, easing: :ease_out)
          child.paint_style(opacity: cx.animator.value(enter_key, 1.0))
        end
      end
      (state[:previous].keys - current.keys).each do |key|
        child, old_bounds = state[:previous][key]
        exit_key = [:exit, identity, key]
        state[:departing][key] = {child: child, bounds: old_bounds}
        cx.animator.animate(exit_key, from: 1.0, to: 0.0, duration: duration, easing: :ease_in) do
          state[:departing].delete(key)
        end
      end
      state[:previous] = keyed.to_h { |key, child| [key, [child, child.layout_node.bounds]] }
      state[:initialized] = true
      @departing_children = state[:departing].map do |key, departure|
        [departure[:child], departure[:bounds], cx.animator.value([:exit, identity, key], 0.0)]
      end
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
