# frozen_string_literal: true

module Zaniah
  class Text < Element
    def initialize(text, size: 14, color: "#ddd", font: nil)
      super()
      @text, @font_size, @color, @font = text, size, color, font
    end

    def measured(&block) = (@measure = block; self)

    def request_layout(cx)
      @line = cx.text_system&.layout_line(@text, font: @font, size: @font_size)
      measurement = @measure || ->(_width, _height) { [@line ? @line.width : @text.length * @font_size * 0.6, @font_size * 1.4, @font_size] }
      @layout_node = Layout::Node.new(style: @style, measure: measurement)
    end

    def paint(bounds, state, prepaint, cx)
      super
      cx.text_system&.paint_line(cx.scene, @line, x: bounds.x, y: bounds.y + @line.ascent, color: @color) if @line
      cx.window.text_runs << [bounds.x, bounds.y, @text, @color] if cx.window.respond_to?(:text_runs)
    end
  end
end
