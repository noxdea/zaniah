# frozen_string_literal: true

module Zaniah
  module TextSystem
    class Paragraph
      Line = Data.define(:layout, :start, :finish, :x, :y, :height)
      attr_reader :text, :lines, :width, :height

      def initialize(text, width:, size: 14, font: nil, wrap: :word, line_height: nil,
        letter_spacing: 0, align: :start, ellipsis: false, kinsoku: :push, typesetter: nil)
        raise ArgumentError, "text must be valid UTF-8" unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
        raise ArgumentError, "align must be start, center, end, or justify" unless %i[start center end justify].include?(align)
        raise ArgumentError, "letter spacing must be finite" unless letter_spacing.is_a?(Numeric) && letter_spacing.finite?
        @text, @limit, @size, @font = text.dup.freeze, Float(width), size, font
        raise ArgumentError, "width must be finite or infinity and nonnegative" if @limit.nan? || @limit.negative?
        @typesetter, @letter_spacing, @align, @ellipsis = typesetter, letter_spacing.to_f, align, ellipsis
        raise ArgumentError, "line height must be numeric" if line_height && !line_height.is_a?(Numeric)
        @line_height = line_height ? (line_height <= 4 ? size * line_height : line_height) : size * 1.4
        raise ArgumentError, "line height must be finite and positive" unless @line_height.is_a?(Numeric) && @line_height.finite? && @line_height.positive?
        breaker = LineBreaker.new(@text, wrap: wrap, kinsoku: kinsoku)
        ranges = breaker.ranges(@limit) { |value| layout(value).width }
        @lines = ranges.each_with_index.map do |range, index|
          source = @text.byteslice(range) || ""
          source = ellipsize(source) if @ellipsis && wrap == :none
          line = spaced(layout(source))
          line = justified(line) if @align == :justify && index < ranges.length - 1
          x = case @align
          when :center then [(@limit - line.width) / 2.0, 0].max
          when :end then [@limit - line.width, 0].max
          else 0.0
          end
          x = 0.0 if @limit.infinite?
          Line.new(line, range.begin, range.end, x, index * @line_height, @line_height)
        end.freeze
        @width = [@lines.map { |line| line.x + line.layout.width }.max || 0, @limit].min
        @height = @lines.length * @line_height
      end

      def hit_test(point)
        return 0 if @lines.empty?
        line = @lines[(point.y / @line_height).floor.clamp(0, @lines.length - 1)]
        [line.start + line.layout.index_for_x(point.x - line.x), line.finish].min
      end

      def offset_to_point(offset)
        offset = Integer(offset).clamp(0, @text.bytesize)
        line = @lines.find { |item| offset <= item.finish } || @lines.last
        Point.new(line.x + line.layout.x_for_index((offset - line.start).clamp(0, line.layout.text.bytesize)), line.y)
      end

      def line_range_at(offset)
        line = @lines.find { |item| offset <= item.finish } || @lines.last
        line.start...line.finish
      end

      private

      def layout(value)
        return @typesetter.layout_line(value, font: @font, size: @size) if @typesetter
        byte, x, carets = 0, 0.0, [[0, 0.0]]
        value.grapheme_clusters.each do |cluster|
          byte += cluster.bytesize
          x += Unicode.width(cluster) * @size * 0.6
          carets << [byte, x]
        end
        LineLayout.new(value.dup.freeze, [].freeze, x, @size, @size * 0.4, @size, carets.freeze)
      end

      def spaced(line)
        return line if @letter_spacing.zero? || line.carets.length < 2
        last = line.carets.length - 1
        carets = line.carets.each_with_index.map { |(byte, x), index| [byte, x + [index, last - 1].min.clamp(0, last) * @letter_spacing] }
        glyphs = line.glyphs.map do |glyph|
          index = line.carets.bsearch_index { |byte, _| byte >= glyph.start } || line.carets.length - 1
          Glyph.new(glyph.font, glyph.id, glyph.start, glyph.finish, glyph.x + index * @letter_spacing, glyph.advance)
        end
        LineLayout.new(line.text, glyphs.freeze, carets.last.last, line.ascent, line.descent, line.size, carets.freeze)
      end

      def justified(line)
        spaces = []
        line.text.to_enum(:scan, /\s+/).each { spaces << Regexp.last_match.end(0) }
        return line if spaces.empty? || @limit.infinite? || line.width >= @limit
        extra = (@limit - line.width) / spaces.length
        shift = ->(byte) { spaces.count { |finish| finish <= byte } * extra }
        carets = line.carets.map { |byte, x| [byte, x + shift.call(byte)] }
        glyphs = line.glyphs.map { |glyph| Glyph.new(glyph.font, glyph.id, glyph.start, glyph.finish, glyph.x + shift.call(glyph.start), glyph.advance) }
        LineLayout.new(line.text, glyphs.freeze, @limit, line.ascent, line.descent, line.size, carets.freeze)
      end

      def ellipsize(value)
        return value if @limit.infinite? || layout(value).width <= @limit
        clusters = value.grapheme_clusters
        clusters.pop while !clusters.empty? && layout(clusters.join + "…").width > @limit
        clusters.join + "…"
      end
    end
  end
end
