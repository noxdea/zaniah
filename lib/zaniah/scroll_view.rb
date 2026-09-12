# frozen_string_literal: true

module Zaniah
  class ScrollView < Element
    attr_reader :scroll_state, :axis

    def initialize(axis: :vertical, scrollbar: :overlay)
      super()
      raise ArgumentError, "scrollbar must be overlay, always, or hidden" unless %i[overlay always hidden].include?(scrollbar)
      @axis, @scrollbar = axis, scrollbar
      @scroll_state = ScrollState.new(axis: axis)
      @scrollbars = []
      unless scrollbar == :hidden
        @scrollbars << UI::Scrollbar.new(@scroll_state, axis: :vertical, mode: scrollbar)
          .style(position: :absolute, right: 2, top: 2, bottom: 2) unless axis == :horizontal
        @scrollbars << UI::Scrollbar.new(@scroll_state, axis: :horizontal, mode: scrollbar)
          .style(position: :absolute, left: 2, right: 2, bottom: 2) unless axis == :vertical
      end
      style(overflow: :hidden)
      on_scroll_wheel do |event, cx|
        delta = axis == :vertical ? Point.new(0, event.delta.y) : axis == :horizontal ? Point.new(event.delta.x, 0) : event.delta
        @scroll_state.glide_by(delta, animator: cx.animator, key: [:scroll, object_id],
          duration: cx.theme.motion.reduced? ? 0 : cx.theme.motion.duration_slow)
        cx.window.request_frame
      end
    end

    def request_layout(cx)
      raise ArgumentError, "ScrollView accepts one child" if @children.length > 1
      if cx.respond_to?(:animator)
        @scroll_state.animation(animator: cx.animator, key: [:scroll, object_id],
          duration: cx.theme.motion.reduced? ? 0 : cx.theme.motion.duration_slow)
      end
      @scroll_state.sample_glide
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
      scrollbar_nodes = @scrollbars.map { |scrollbar_element| scrollbar_element.request_layout(cx) }
      @layout_node = Layout::Node.new(style: @style, children: (node ? [node] : []) + scrollbar_nodes, measure: ->(*) { [viewport.width, viewport.height] })
    end

    def prepaint(bounds, state, cx)
      apply_sticky(@children.first, bounds) if @children.first
      super
      @scrollbars.each { |scrollbar_element| scrollbar_element.prepaint(scrollbar_element.layout_node.bounds, nil, cx) }
    end

    def paint(bounds, state, prepaint, cx)
      super
      @scrollbars.each { |scrollbar_element| scrollbar_element.paint(scrollbar_element.layout_node.bounds, nil, nil, cx) }
    end

    def scroll_to(target, align: :nearest, animate: false)
      if target.is_a?(Bounds)
        previous = @scroll_state.offset
        @scroll_state.scroll_rect(target, align: align)
        destination = @scroll_state.offset
        @scroll_state.offset = previous if animate
        @scroll_state.scroll_to(destination, animate: animate)
      else
        @scroll_state.scroll_to(target, animate: animate)
      end
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
