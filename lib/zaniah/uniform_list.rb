# frozen_string_literal: true

module Zaniah
  class UniformList < Element
    attr_reader :visible_range, :scroll_state

    def initialize(count:, row_height:, &render_item)
      super()
      raise ArgumentError, "invalid list dimensions" unless count >= 0 && row_height.positive?
      @count, @row_height, @render_item = count, row_height, render_item
      @scroll_state = ScrollState.new(axis: :vertical)
      @scroll_state.update(content_size: Size.new(0, count * row_height), viewport_size: Size.new(0, 0))
      style(overflow: :hidden)
      on_scroll_wheel do |event, cx|
        @scroll_state.scroll_by(event.delta.y)
        cx.window.request_frame
      end
    end

    def scroll_y = @scroll_state.offset.y

    def scroll_y=(value)
      @scroll_state.scroll_to(value)
    end

    def request_layout(cx)
      viewport = @style[:height]
      viewport = viewport.resolve(cx.window.content_size.height) if viewport.is_a?(Length)
      viewport = cx.window.content_size.height unless viewport.is_a?(Numeric)
      width = @style[:width]
      width = width.resolve(cx.window.content_size.width) if width.is_a?(Length)
      width = cx.window.content_size.width unless width.is_a?(Numeric)
      @scroll_state.update(content_size: Size.new(width, @count * @row_height), viewport_size: Size.new(width, viewport))
      first = (scroll_y / @row_height).floor
      last = [first + (viewport / @row_height).ceil + 1, @count].min
      @visible_range = first...last
      @children = @visible_range.map do |index|
        @render_item.call(index).style(position: :absolute, left: 0, right: 0,
          top: index * @row_height - scroll_y, height: @row_height)
      end
      @children.each { |child| child.send(:parent=, self) }
      super
    end
  end
end
