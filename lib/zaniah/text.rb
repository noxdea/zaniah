# frozen_string_literal: true

module Zaniah
  class Text < Element
    attr_reader :text, :font_size

    def initialize(text, size: 14, color: "#ddd", font: nil)
      super()
      @text, @font_size, @color, @font = text, size, color, font
    end

    def measured(&block) = (@measure = block; self)
    def text_color = @color

    def request_layout(cx)
      @line = cx.text_system&.layout_line(@text, font: @font, size: @font_size)
      line_height = @line ? @line.ascent + @line.descent : 0
      measurement = @measure || ->(_width, _height) { [@line ? @line.width : @text.length * @font_size * 0.6, [@font_size * 1.4, line_height].max, @font_size] }
      @layout_node = Layout::Node.new(style: @style, measure: measurement)
    end

    def paint(bounds, state, prepaint, cx)
      super
      color = @resolved_style[:text_color] || @color
      cx.text_system&.paint_line(cx.scene, @line, x: bounds.x, y: bounds.y + @line.ascent, color: color) if @line
      cx.window.text_runs << [bounds.x, bounds.y, @text, color] if cx.window.respond_to?(:text_runs)
    end
  end
end
