# frozen_string_literal: true

module Zaniah
  class UniformList < Element
    attr_accessor :scroll_y
    attr_reader :visible_range

    def initialize(count:, row_height:, &render_item)
      super()
      raise ArgumentError, "invalid list dimensions" unless count >= 0 && row_height.positive?
      @count, @row_height, @render_item, @scroll_y = count, row_height, render_item, 0
      style(overflow: :hidden)
    end

    def request_layout(cx)
      viewport = @style[:height]
      viewport = viewport.resolve(cx.window.content_size.height) if viewport.is_a?(Length)
      viewport = cx.window.content_size.height unless viewport.is_a?(Numeric)
      @scroll_y = @scroll_y.clamp(0, [@count * @row_height - viewport, 0].max)
      first = (@scroll_y / @row_height).floor
      last = [first + (viewport / @row_height).ceil + 1, @count].min
      @visible_range = first...last
      @children = @visible_range.map do |index|
        @render_item.call(index).style(position: :absolute, left: 0, right: 0,
          top: index * @row_height - @scroll_y, height: @row_height)
      end
      super
    end
  end
end
