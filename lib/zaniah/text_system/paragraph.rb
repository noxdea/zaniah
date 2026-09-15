# frozen_string_literal: true

module Zaniah
  module TextSystem
    class Paragraph
      Line = Data.define(:layout, :start, :finish, :x, :y, :height)
      InlineOverlay = Data.define(:key, :offset, :width, :height, :align)
      Placement = Data.define(:key, :offset, :x, :y, :width, :height, :line, :align)
      attr_reader :text, :lines, :width, :height, :inline_placements

      def initialize(text, width:, size: 14, font: nil, wrap: :word, line_height: nil,
        letter_spacing: 0, align: :start, ellipsis: false, kinsoku: :push, typesetter: nil,
        inline_overlays: [])
        raise ArgumentError, "text must be valid UTF-8" unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
        raise ArgumentError, "align must be start, center, end, or justify" unless %i[start center end justify].include?(align)
        raise ArgumentError, "letter spacing must be finite" unless letter_spacing.is_a?(Numeric) && letter_spacing.finite?
        @text, @limit, @size, @font = text.dup.freeze, Float(width), size, font
        raise ArgumentError, "width must be finite or infinity and nonnegative" if @limit.nan? || @limit.negative?
        @typesetter, @letter_spacing, @align, @ellipsis = typesetter, letter_spacing.to_f, align, ellipsis
        raise ArgumentError, "line height must be numeric" if line_height && !line_height.is_a?(Numeric)
        @line_height = line_height ? (line_height <= 4 ? size * line_height : line_height) : size * 1.4
        raise ArgumentError, "line height must be finite and positive" unless @line_height.is_a?(Numeric) && @line_height.finite? && @line_height.positive?
        @inline_overlays = validate_overlays(inline_overlays)
        breaker = LineBreaker.new(@text, wrap: wrap, kinsoku: kinsoku)
        ranges = breaker.ranges_with_offsets(@limit) do |value, first, finish|
          layout_with_overlays(value, first, overlays_for(first, finish)).width
        end
        y, @inline_placements = 0.0, []
        @lines = ranges.each_with_index.map do |range, index|
          source = @text.byteslice(range) || ""
          source = ellipsize(source, range.begin) if @ellipsis && wrap == :none
          overlays = overlays_for(range.begin, range.end).select { |overlay| overlay.offset - range.begin <= source.bytesize }
          line = spaced(layout_with_overlays(source, range.begin, overlays))
          line = justified(line) if @align == :justify && index < ranges.length - 1
          height = [@line_height, overlays.map(&:height).max || 0].max
          x = case @align
          when :center then [(@limit - line.width) / 2.0, 0].max
          when :end then [@limit - line.width, 0].max
          else 0.0
          end
          x = 0.0 if @limit.infinite?
          append_placements(overlays, line, range.begin, x, y, height, index)
          Line.new(line, range.begin, range.end, x, y, height).tap { y += height }
        end.freeze
        @inline_placements.freeze
        @width = [@lines.map { |line| line.x + line.layout.width }.max || 0, @limit].min
        @height = y
      end

      def hit_test(point)
        return 0 if @lines.empty?
        if (overlay = @inline_placements.find { |item| Bounds.new(item.x, item.y, item.width, item.height).contains?(point) })
          return overlay.offset
        end
        line = @lines.find { |item| point.y < item.y + item.height } || @lines.last
        [line.start + line.layout.index_for_x(point.x - line.x), line.finish].min
      end

      def offset_to_point(offset)
        offset = Integer(offset).clamp(0, @text.bytesize)
        placement = @inline_placements.find { |item| item.offset == offset && item.align == :before }
        line = placement ? @lines.fetch(placement.line) : @lines.find { |item| offset <= item.finish } || @lines.last
        Point.new(line.x + line.layout.x_for_index((offset - line.start).clamp(0, line.layout.text.bytesize)), line.y)
      end

      def line_range_at(offset)
        line = @lines.find { |item| offset <= item.finish } || @lines.last
        line.start...line.finish
      end

      private

      def validate_overlays(overlays)
        raise ArgumentError, "inline overlays must be an array" unless overlays.is_a?(Array)
        overlays.map do |overlay|
          unless overlay.is_a?(InlineOverlay) && overlay.offset.is_a?(Integer) && overlay.offset.between?(0, @text.bytesize) &&
              Unicode.grapheme_boundary?(@text, overlay.offset) && %i[before after].include?(overlay.align) &&
              [overlay.width, overlay.height].all? { |value| value.is_a?(Numeric) && value.finite? && !value.negative? }
            raise ArgumentError, "invalid inline overlay"
          end
          overlay
        end.sort_by { |overlay| [overlay.offset, overlay.align == :before ? 0 : 1] }.freeze
      end

      def overlays_for(first, finish)
        @inline_overlays.select do |overlay|
          (overlay.offset > first && overlay.offset < finish) ||
            (overlay.offset == first && (first.zero? || @text.getbyte(first - 1) == 10 || overlay.align == :before)) ||
            (overlay.offset == finish && (finish == @text.bytesize || @text.getbyte(finish) == 10 || overlay.align == :after))
        end
      end

      def layout_with_overlays(value, start, overlays)
        return layout(value) if overlays.empty?
        boundaries = overlays.map { |overlay| overlay.offset - start }.uniq.sort
        glyphs, carets, cursor, first = [], [[0, 0.0]], 0.0, 0
        boundaries.each do |boundary|
          part = layout(value.byteslice(first...boundary) || "")
          append_layout(glyphs, carets, part, first, cursor)
          cursor += part.width
          at = overlays.select { |overlay| overlay.offset - start == boundary }
          before = at.sum { |overlay| overlay.align == :before ? overlay.width : 0 }
          carets[-1] = [boundary, cursor + before]
          cursor += at.sum(&:width)
          first = boundary
        end
        part = layout(value.byteslice(first..-1) || "")
        append_layout(glyphs, carets, part, first, cursor)
        cursor += part.width
        LineLayout.new(value.dup.freeze, glyphs.freeze, cursor, part.ascent, part.descent, part.size, carets.freeze)
      end

      def append_layout(glyphs, carets, line, byte, x)
        line.glyphs.each do |glyph|
          glyphs << Glyph.new(glyph.font, glyph.id, glyph.start + byte, glyph.finish + byte, glyph.x + x, glyph.advance)
        end
        line.carets.drop(1).each { |offset, position| carets << [offset + byte, position + x] }
      end

      def append_placements(overlays, line, start, x, y, height, line_index)
        overlays.group_by(&:offset).each do |offset, group|
          caret = line.x_for_index(offset - start)
          before = group.select { |overlay| overlay.align == :before }
          after = group.select { |overlay| overlay.align == :after }
          cursor = x + caret - before.sum(&:width)
          (before + after).each do |overlay|
            @inline_placements << Placement.new(overlay.key, offset, cursor,
              y + (height - overlay.height) / 2.0, overlay.width, overlay.height, line_index, overlay.align)
            cursor += overlay.width
          end
        end
      end

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
        trailing = line.width - line.carets.last.last
        LineLayout.new(line.text, glyphs.freeze, carets.last.last + trailing, line.ascent, line.descent, line.size, carets.freeze)
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

      def ellipsize(value, start)
        overlays = overlays_for(start, start + value.bytesize)
        return value if @limit.infinite? || layout_with_overlays(value, start, overlays).width <= @limit
        clusters = value.grapheme_clusters
        clusters.pop while !clusters.empty? && layout_with_overlays(clusters.join + "…", start,
          overlays.select { |overlay| overlay.offset - start <= clusters.join.bytesize }).width > @limit
        clusters.join + "…"
      end
    end

    class OverlayParagraph
      Row = Data.define(:paragraph, :start)
      Block = Data.define(:key, :line, :offset, :width, :height, :position)

      attr_reader :text, :lines, :width, :height, :inline_placements, :block_placements

      def initialize(text, rows:, blocks:, width:)
        @text, @lines, @inline_placements, @block_placements = text, [], [], []
        y = 0.0
        rows.each_with_index do |row, row_index|
          y = append_blocks(blocks, row_index, :above, y)
          first_line = @lines.length
          row.paragraph.lines.each do |line|
            @lines << Paragraph::Line.new(line.layout, line.start + row.start,
              line.finish + row.start, line.x, line.y + y, line.height)
          end
          row.paragraph.inline_placements.each do |placement|
            @inline_placements << placement.with(offset: placement.offset + row.start,
              y: placement.y + y, line: placement.line + first_line)
          end
          y += row.paragraph.height
          y = append_blocks(blocks, row_index, :below, y)
        end
        @lines.freeze
        @inline_placements.freeze
        @block_placements.freeze
        @width = [[@lines.map { |line| line.x + line.layout.width }.max || 0,
          @block_placements.map { |placement| placement.x + placement.width }.max || 0].max, width].min
        @height = y
      end

      def hit_test(point)
        placements = @inline_placements + @block_placements
        if (overlay = placements.find { |item| Bounds.new(item.x, item.y, item.width, item.height).contains?(point) })
          return overlay.offset
        end
        return 0 if @lines.empty?
        line = @lines.find { |item| point.y < item.y + item.height } || @lines.last
        [line.start + line.layout.index_for_x(point.x - line.x), line.finish].min
      end

      def offset_to_point(offset)
        offset = Integer(offset).clamp(0, @text.bytesize)
        placement = @inline_placements.find { |item| item.offset == offset && item.align == :before }
        line = placement ? @lines.fetch(placement.line) : @lines.find { |item| offset <= item.finish } || @lines.last
        Point.new(line.x + line.layout.x_for_index((offset - line.start).clamp(0, line.layout.text.bytesize)), line.y)
      end

      def line_range_at(offset)
        line = @lines.find { |item| offset <= item.finish } || @lines.last
        line.start...line.finish
      end

      private

      def append_blocks(blocks, line, position, y)
        blocks.each do |block|
          next unless block.line == line && block.position == position
          @block_placements << Paragraph::Placement.new(block.key, block.offset, 0, y,
            block.width, block.height, line, position)
          y += block.height
        end
        y
      end
    end
  end
end
