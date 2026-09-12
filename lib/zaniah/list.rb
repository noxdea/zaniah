# frozen_string_literal: true

module Zaniah
  # A variable-height, viewport-only list. Unknown rows use estimated_height;
  # measuring visible rows refines the prefix sums without moving the anchor.
  class List < Element
    attr_reader :visible_range, :heights, :scroll_state

    def initialize(count:, estimated_height: 24, overscan: 2, &render_item)
      super()
      raise ArgumentError, "a row renderer is required" unless render_item
      raise ArgumentError, "overscan must be a nonnegative integer" unless overscan.is_a?(Integer) && overscan >= 0
      @heights, @overscan, @render_item = HeightIndex.new(count, estimated_height), overscan, render_item
      @scroll_state = ScrollState.new(axis: :vertical)
      @scroll_state.update(content_size: Size.new(0, @heights.total), viewport_size: Size.new(0, 0))
      @viewport, @visible_range = 0.0, 0...0
      style(overflow: :hidden)
      on_scroll_wheel do |event, cx|
        @scroll_state.glide_by(event.delta.y, animator: cx.animator, key: [:scroll, object_id],
          duration: cx.theme.motion.reduced? ? 0 : cx.theme.motion.duration_slow)
        cx.window.request_frame
      end
    end

    def total_height = @heights.total
    def scroll_y = @scroll_state.offset.y

    def scroll_y=(value)
      @scroll_state.scroll_to(value)
      value
    end

    def update_height(index, height)
      anchor = @heights.index_at(scroll_y)
      delta = @heights.update(index, height)
      @scroll_state.update(content_size: Size.new(@scroll_state.content_size.width, total_height), viewport_size: @scroll_state.viewport_size)
      @scroll_state.preserve_anchor(delta) if index < anchor
      self
    end

    def scroll_to(index, align: :start)
      height, top = @heights[index], @heights.prefix(index)
      offset = case align
      when :start then top
      when :center then top - (@viewport - height) / 2
      when :end then top + height - @viewport
      when :nearest
        top < scroll_y ? top : (top + height > scroll_y + @viewport ? top + height - @viewport : scroll_y)
      else raise ArgumentError, "unknown alignment #{align.inspect}"
      end
      self.scroll_y = offset
      self
    end

    def request_layout(cx)
      @state = cx.state(@key, &@state_initializer) if @key && @state_initializer
      if cx.respond_to?(:animator)
        @scroll_state.animation(animator: cx.animator, key: [:scroll, object_id],
          duration: cx.theme.motion.reduced? ? 0 : cx.theme.motion.duration_slow)
      end
      @scroll_state.sample_glide
      @viewport = dimension(:height, cx.window.content_size.height)
      width = dimension(:width, cx.window.content_size.width)
      @scroll_state.update(content_size: Size.new(width, total_height), viewport_size: Size.new(width, @viewport))
      anchor = @heights.index_at(scroll_y)
      within = scroll_y - @heights.prefix(anchor)
      measured, engine = {}, Layout::Engine.new
      loop do
        @visible_range = viewport_range
        missing = @visible_range.reject { |index| measured.key?(index) }
        break if missing.empty?
        missing.each do |index|
          element = @render_item.call(index)
          raise TypeError, "row renderer must return a renderable element" unless element.respond_to?(:request_layout) && element.respond_to?(:prepaint) && element.respond_to?(:paint)
          node = element.request_layout(cx)
          _natural_width, height = engine.measure(node, width: width, height: @viewport)
          @heights.update(index, [height, 1.0].max)
          measured[index] = [element, node]
        end
        @scroll_state.update(content_size: Size.new(width, total_height), viewport_size: Size.new(width, @viewport))
        self.scroll_y = @heights.prefix(anchor) + [within, anchor < @heights.count ? @heights[anchor] : 0].min
      end
      @children = @visible_range.map { |index| measured.fetch(index).first }
      @children.each { |child| child.send(:parent=, self) }
      nodes = @visible_range.map do |index|
        node = measured.fetch(index).last
        node.style = node.style.merge(position: :absolute, left: 0, right: 0,
                                     top: @heights.prefix(index) - scroll_y, height: @heights[index])
        node
      end
      @layout_node = Layout::Node.new(style: @style, children: nodes,
                                     measure: ->(_width, _height) { [width, @viewport] })
    end

    private

    def dimension(property, available)
      value = @style[property]
      value = value.resolve(available) if value.is_a?(Length)
      value.is_a?(Numeric) ? [value, 0].max : available
    end

    def viewport_range
      return 0...0 if @heights.count.zero? || @viewport.zero?
      first = [@heights.index_at(scroll_y) - @overscan, 0].max
      last = [@heights.index_at(scroll_y + @viewport) + 1 + @overscan, @heights.count].min
      first...last
    end
  end

end

require_relative "list/height_index"
