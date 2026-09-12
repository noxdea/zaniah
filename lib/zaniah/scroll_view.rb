# frozen_string_literal: true

module Zaniah
  class ScrollView < Element
    attr_reader :scroll_state, :axis

    def initialize(axis: :vertical, scrollbar: :overlay)
      super()
      raise ArgumentError, "scrollbar must be overlay, always, or hidden" unless %i[overlay always hidden].include?(scrollbar)
      @axis, @scrollbar = axis, scrollbar
      @scroll_state = ScrollState.new(axis: axis)
      style(overflow: :hidden)
      on_scroll_wheel do |event, cx|
        delta = axis == :vertical ? Point.new(0, event.delta.y) : axis == :horizontal ? Point.new(event.delta.x, 0) : event.delta
        @scroll_state.scroll_by(delta)
        cx.window.request_frame
      end
    end

    def request_layout(cx)
      raise ArgumentError, "ScrollView accepts one child" if @children.length > 1
      viewport = Size.new(dimension(:width, cx.window.content_size.width), dimension(:height, cx.window.content_size.height))
      node = @children.first&.request_layout(cx)
      if node
        natural = Layout::Engine.new.measure(node, width: viewport.width, height: viewport.height)
        content = Size.new([natural[0], viewport.width].max, [natural[1], viewport.height].max)
        @scroll_state.update(content_size: content, viewport_size: viewport)
        node.style = node.style.merge(position: :absolute, left: -@scroll_state.offset.x,
          top: -@scroll_state.offset.y, width: content.width, height: content.height)
      else
        @scroll_state.update(content_size: viewport, viewport_size: viewport)
      end
      @layout_node = Layout::Node.new(style: @style, children: node ? [node] : [], measure: ->(*) { [viewport.width, viewport.height] })
    end

    def prepaint(bounds, state, cx)
      apply_sticky(@children.first, bounds) if @children.first
      super
    end

    def scroll_to(target, align: :nearest, animate: false)
      target.is_a?(Bounds) ? @scroll_state.scroll_rect(target, align: align) : @scroll_state.scroll_to(target, animate: animate)
      self
    end

    private

    def dimension(property, available)
      value = @style[property]
      value = value.resolve(available) if value.is_a?(Length)
      value.is_a?(Numeric) ? [value, 0].max : available
    end

    def apply_sticky(element, viewport)
      element.children.each do |child|
        node = child.layout_node
        if node.style[:position] == :sticky
          top = node.style[:top].is_a?(Numeric) ? node.style[:top] : 0
          node.bounds = Bounds.new(node.bounds.x, [node.bounds.y, viewport.y + top].max,
            node.bounds.width, node.bounds.height)
        end
        apply_sticky(child, viewport)
      end
    end
  end
end
