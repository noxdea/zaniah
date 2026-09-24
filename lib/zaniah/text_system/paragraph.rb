# frozen_string_literal: true

module Zaniah
  module TextSystem
    class Paragraph
      Line = Data.define(:layout, :start, :finish, :x, :y, :height)
      InlineOverlay = Data.define(:key, :offset, :width, :height, :align)
      Placement = Data.define(:key, :offset, :x, :y, :width, :height, :line, :align)
      attr_reader :text, :lines, :width, :height, :inline_placements, :direction, :writing_mode, :text_orientation

      def initialize(text, width:, size: 14, font: nil, wrap: :word, line_height: nil,
        letter_spacing: 0, align: :start, ellipsis: false, kinsoku: :push, typesetter: nil,
        inline_overlays: [], direction: :auto, writing_mode: :horizontal_tb, text_orientation: :mixed)
        raise ArgumentError, "text must be valid UTF-8" unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
        raise ArgumentError, "align must be start, center, end, or justify" unless %i[start center end justify].include?(align)
        raise ArgumentError, "letter spacing must be finite" unless letter_spacing.is_a?(Numeric) && letter_spacing.finite?
        raise ArgumentError, "direction must be auto, ltr, or rtl" unless %i[auto ltr rtl].include?(direction)
        raise ArgumentError, "writing mode must be horizontal_tb or vertical_rl" unless %i[horizontal_tb vertical_rl].include?(writing_mode)
        raise ArgumentError, "text orientation must be mixed or upright" unless %i[mixed upright].include?(text_orientation)
        @writing_mode, @text_orientation = writing_mode, text_orientation
        @text, @limit, @size, @font = text.dup.freeze, Float(width), size, font
        if @text.ascii_only? && direction != :rtl
          @row_bidi, @direction = nil, :ltr
        else
          byte = 0
          resolved_rows = {}
          rows = @text.empty? ? [""] : @text.split("\n", -1)
          @row_bidi = rows.map do |row|
            result = resolved_rows[row] ||= Unicode::Bidi.resolve(row, direction: direction)
            item = [byte, byte + row.bytesize, row, result]
            byte += row.bytesize + 1
            item
          end
          @direction = @row_bidi.first.last.direction
        end
        raise ArgumentError, "width must be finite or infinity and nonnegative" if @limit.nan? || @limit.negative?
        @typesetter, @letter_spacing, @align, @ellipsis = typesetter, letter_spacing.to_f, align, ellipsis
        if @typesetter
          params = @typesetter.method(:layout_line).parameters
          accepts_rest = params.any? { |kind, _| kind == :keyrest }
          @accepts_direction = accepts_rest || params.any? { |kind, key| key == :direction && %i[key keyreq].include?(kind) }
          @accepts_bidi = accepts_rest || params.any? { |kind, key| key == :bidi && %i[key keyreq].include?(kind) }
          @accepts_writing_mode = accepts_rest || params.any? { |kind, key| key == :writing_mode && %i[key keyreq].include?(kind) }
        end
        raise ArgumentError, "line height must be numeric" if line_height && !line_height.is_a?(Numeric)
        @line_height = line_height ? (line_height <= 4 ? size * line_height : line_height) : size * 1.4
        raise ArgumentError, "line height must be finite and positive" unless @line_height.is_a?(Numeric) && @line_height.finite? && @line_height.positive?
        @inline_overlays = validate_overlays(inline_overlays)
        @inline_overlays = @inline_overlays.map { |overlay| overlay.with(width: overlay.height, height: overlay.width) }.freeze if @writing_mode == :vertical_rl
        breaker = LineBreaker.new(@text, wrap: wrap, kinsoku: kinsoku)
        ranges = breaker.ranges_with_offsets(@limit) do |value, first, finish|
          layout_with_overlays(value, first, overlays_for(first, finish)).width
        end
        y, @inline_placements = 0.0, []
        @lines = ranges.each_with_index.map do |range, index|
          source = @text.byteslice(range) || ""
          visible = source.bytesize
          source, visible = ellipsize(source, range.begin) if @ellipsis && wrap == :none
          overlays = overlays_for(range.begin, range.end).select { |overlay| overlay.offset - range.begin <= visible }
          line = spaced(layout_with_overlays(source, range.begin, overlays))
          line = justified(line) if @align == :justify && index < ranges.length - 1 && !line.visual_carets
          row_direction = @row_bidi && @writing_mode != :vertical_rl ? row_for(range.begin).last.direction : :ltr
          height = [@line_height, overlays.map(&:height).max || 0].max
          x = case @align
          when :center then [(@limit - line.width) / 2.0, 0].max
          when :end then row_direction == :rtl ? 0.0 : [@limit - line.width, 0].max
          when :start then row_direction == :rtl ? [@limit - line.width, 0].max : 0.0
          else 0.0
          end
          x = 0.0 if @limit.infinite?
          append_placements(overlays, line, range.begin, x, y, height, index)
          Line.new(line, range.begin, range.end, x, y, height).tap { y += height }
        end.freeze
        if @writing_mode == :vertical_rl
          cross = @lines.sum(&:height)
          used = 0.0
          @lines = @lines.map do |line|
            used += line.height
            line.with(x: cross - used, y: line.x)
          end.freeze
          @inline_placements = @inline_placements.map do |item|
            item.with(x: cross - item.y - item.height, y: item.x,
              width: item.height, height: item.width)
          end
        end
        @inline_placements.freeze
        @width = @writing_mode == :vertical_rl ? y : [@lines.map { |line| line.x + line.layout.width }.max || 0, @limit].min
        @height = @writing_mode == :vertical_rl ? [@lines.map { |line| line.y + line.layout.width }.max || 0, @limit].min : y
      end

      def hit_test(point)
        hit_test_with_affinity(point).first
      end

      def hit_test_with_affinity(point)
        return [0, :downstream] if @lines.empty?
        if (overlay = @inline_placements.find { |item| Bounds.new(item.x, item.y, item.width, item.height).contains?(point) })
          return [overlay.offset, :downstream]
        end
        if @writing_mode == :vertical_rl
          line = @lines.find { |item| point.x >= item.x && point.x < item.x + item.height } ||
            (point.x >= @lines.first.x + @lines.first.height ? @lines.first : @lines.last)
          offset, affinity = line.layout.hit_test(point.y - line.y)
          return [[line.start + offset, line.finish].min, affinity]
        end
        line = @lines.find { |item| point.y < item.y + item.height } || @lines.last
        offset, affinity = line.layout.hit_test(point.x - line.x)
        [[line.start + offset, line.finish].min, affinity]
      end

      def offset_to_point(offset, affinity: :downstream)
        offset = Integer(offset).clamp(0, @text.bytesize)
        placement = @inline_placements.find { |item| item.offset == offset && item.align == :before }
        line = placement ? @lines.fetch(placement.line) : @lines.find { |item| offset <= item.finish } || @lines.last
        inline = line.layout.caret_x((offset - line.start).clamp(0, line.layout.text.bytesize), affinity: affinity)
        @writing_mode == :vertical_rl ? Point.new(line.x, line.y + inline) : Point.new(line.x + inline, line.y)
      end

      def selection_rects(range)
        @lines.flat_map do |line|
          first, last = [range.begin, line.start].max, [range.end, line.finish].min
          next [] unless last > first
          line.layout.selection_rects((first - line.start)...(last - line.start)).map do |rect|
            if @writing_mode == :vertical_rl
              Bounds.new(line.x, line.y + rect.x, line.height, rect.width)
            else
              Bounds.new(line.x + rect.x, line.y, rect.width, line.height)
            end
          end
        end
      end

      def line_range_at(offset)
        line = @lines.find { |item| offset <= item.finish } || @lines.last
        line.start...line.finish
      end

      private

      def validate_overlays(overlays)
        raise ArgumentError, "inline overlays must be an array" unless overlays.is_a?(Array)
        overlays.map.with_index do |overlay, index|
          unless overlay.is_a?(InlineOverlay) && overlay.offset.is_a?(Integer) && overlay.offset.between?(0, @text.bytesize) &&
              Unicode.grapheme_boundary?(@text, overlay.offset) && %i[before after].include?(overlay.align) &&
              [overlay.width, overlay.height].all? { |value| value.is_a?(Numeric) && value.finite? && !value.negative? }
            raise ArgumentError, "invalid inline overlay"
          end
          [overlay, index]
        end.sort_by { |overlay, index| [overlay.offset, overlay.align == :before ? 0 : 1, index] }
          .map!(&:first).freeze
      end

      def overlays_for(first, finish)
        @inline_overlays.select do |overlay|
          (overlay.offset > first && overlay.offset < finish) ||
            (overlay.offset == first && (first.zero? || @text.getbyte(first - 1) == 10 || overlay.align == :before)) ||
            (overlay.offset == finish && (finish == @text.bytesize || @text.getbyte(finish) == 10 || overlay.align == :after))
        end
      end

      def row_for(offset)
        index = @row_bidi.bsearch_index { |_, last, _, _| last >= offset }
        @row_bidi.fetch(index || -1)
      end

      def layout_with_overlays(value, start, overlays)
        return layout(value, start) if overlays.empty?
        boundaries = overlays.map { |overlay| overlay.offset - start }.uniq.sort
        glyphs, carets, cursor, first = [], [[0, 0.0]], 0.0, 0
        boundaries.each do |boundary|
          part = layout(value.byteslice(first...boundary) || "", start + first)
          append_layout(glyphs, carets, part, first, cursor)
          cursor += part.width
          at = overlays.select { |overlay| overlay.offset - start == boundary }
          before = at.sum { |overlay| overlay.align == :before ? overlay.width : 0 }
          carets[-1] = [boundary, cursor + before]
          cursor += at.sum(&:width)
          first = boundary
        end
        part = layout(value.byteslice(first..-1) || "", start + first)
        append_layout(glyphs, carets, part, first, cursor)
        cursor += part.width
        LineLayout.new(value.dup.freeze, glyphs.freeze, cursor, part.ascent, part.descent, part.size, carets.freeze, nil, @writing_mode)
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

      def layout(value, start)
        if @typesetter && !@row_bidi && @writing_mode == :horizontal_tb
          return @typesetter.layout_line(value, font: @font, size: @size)
        end
        if @typesetter
          kwargs = {font: @font, size: @size}
          kwargs[:writing_mode] = @writing_mode if @accepts_writing_mode
          if @row_bidi
            row_first, row_last, row_text, row_result = row_for(start)
            kwargs[:direction] = row_result.direction if @accepts_direction
            if @accepts_bidi && start + value.bytesize <= row_last && @text.byteslice(start, value.bytesize) == value
              first = start == row_first ? 0 : row_text.byteslice(0...(start - row_first)).length
              kwargs[:bidi] = Unicode::Bidi.line_result(row_result, row_text, first, first + value.length)
            end
          else
            kwargs[:direction] = :ltr if @accepts_direction
          end
          result = @typesetter.layout_line(value, **kwargs)
          return @writing_mode == :vertical_rl && result.writing_mode != :vertical_rl ? result.with(writing_mode: :vertical_rl) : result
        end
        if @row_bidi
          row_first, row_last, row_text, row_result = row_for(start)
          bidi = if start + value.bytesize <= row_last && @text.byteslice(start, value.bytesize) == value
            first = start == row_first ? 0 : row_text.byteslice(0...(start - row_first)).length
            Unicode::Bidi.line_result(row_result, row_text, first, first + value.length)
          else
            Unicode::Bidi.resolve(value, direction: row_result.direction)
          end
          return approximate_bidi_layout(value, bidi) if bidi.levels.any? { |level| level&.odd? }
        end
        byte, x, carets = 0, 0.0, [[0, 0.0]]
        value.grapheme_clusters.each do |cluster|
          byte += cluster.bytesize
          x += Unicode.width(cluster) * @size * 0.6
          carets << [byte, x]
        end
        LineLayout.new(value.dup.freeze, [].freeze, x, @size, @size * 0.4, @size, carets.freeze, nil, @writing_mode)
      end

      def approximate_bidi_layout(value, bidi)
        clusters, byte, scalar = [], 0, 0
        value.grapheme_clusters.each do |cluster|
          count = cluster.length
          clusters << [byte, byte + cluster.bytesize, scalar, scalar + count,
            Unicode.width(cluster) * @size * 0.6]
          byte += cluster.bytesize
          scalar += count
        end
        owners = Array.new(scalar)
        clusters.each_with_index { |(_first, _finish, from, to, _width), index| (from...to).each { |at| owners[at] = index } }
        order = bidi.visual_order.filter_map { |index| owners[index] }.uniq
        order.concat((0...clusters.length).reject { |index| order.include?(index) })
        visual, x = [], 0.0
        order.each do |index|
          first, finish, scalar_start, _scalar_end, width = clusters[index]
          if bidi.levels[scalar_start]&.odd?
            visual << [finish, :upstream, x]
            visual << [first, :downstream, x + width]
          else
            visual << [first, :downstream, x]
            visual << [finish, :upstream, x + width]
          end
          x += width
        end
        carets = ([0] + clusters.map { |cluster| cluster[1] }).map do |offset|
          caret = visual.find { |byte, affinity, _| byte == offset && affinity == :downstream } ||
            visual.find { |byte, _, _| byte == offset }
          [offset, caret ? caret[2] : x]
        end
        LineLayout.new(value.dup.freeze, [].freeze, x, @size, @size * 0.4, @size,
          carets.freeze, visual.freeze, @writing_mode)
      end

      def spaced(line)
        return line if @letter_spacing.zero? || line.carets.length < 2
        if line.visual_carets
          positions = line.visual_carets.map(&:last).uniq.sort
          shift = ->(x) { ((positions.bsearch_index { |position| position >= x } || positions.length - 1) * @letter_spacing) }
          visual = line.visual_carets.map { |byte, affinity, x| [byte, affinity, x + shift.call(x)] }
          carets = line.carets.map { |byte, x| [byte, x + shift.call(x)] }
          glyphs = line.glyphs.map { |glyph| glyph.with(x: glyph.x + shift.call(glyph.x)) }
          return LineLayout.new(line.text, glyphs.freeze, line.width + (positions.length - 1) * @letter_spacing,
            line.ascent, line.descent, line.size, carets.freeze, visual.freeze, line.writing_mode)
        end
        last = line.carets.length - 1
        carets = line.carets.each_with_index.map { |(byte, x), index| [byte, x + [index, last - 1].min.clamp(0, last) * @letter_spacing] }
        glyphs = line.glyphs.map do |glyph|
          index = line.carets.bsearch_index { |byte, _| byte >= glyph.start } || line.carets.length - 1
          Glyph.new(glyph.font, glyph.id, glyph.start, glyph.finish, glyph.x + index * @letter_spacing, glyph.advance)
        end
        trailing = line.width - line.carets.last.last
        LineLayout.new(line.text, glyphs.freeze, carets.last.last + trailing, line.ascent, line.descent, line.size, carets.freeze, nil, line.writing_mode)
      end

      def justified(line)
        spaces = []
        line.text.to_enum(:scan, /\s+/).each { spaces << Regexp.last_match.end(0) }
        return line if spaces.empty? || @limit.infinite? || line.width >= @limit
        extra = (@limit - line.width) / spaces.length
        shift = ->(byte) { spaces.count { |finish| finish <= byte } * extra }
        carets = line.carets.map { |byte, x| [byte, x + shift.call(byte)] }
        glyphs = line.glyphs.map { |glyph| Glyph.new(glyph.font, glyph.id, glyph.start, glyph.finish, glyph.x + shift.call(glyph.start), glyph.advance) }
        LineLayout.new(line.text, glyphs.freeze, @limit, line.ascent, line.descent, line.size, carets.freeze, nil, line.writing_mode)
      end

      def ellipsize(value, start)
        overlays = overlays_for(start, start + value.bytesize)
        return [value, value.bytesize] if @limit.infinite? || layout_with_overlays(value, start, overlays).width <= @limit
        clusters = value.grapheme_clusters
        clusters.pop while !clusters.empty? && layout_with_overlays(clusters.join + "…", start,
          overlays.select { |overlay| overlay.offset - start <= clusters.join.bytesize }).width > @limit
        visible = clusters.join
        [visible + "…", visible.bytesize]
      end
    end

    class OverlayParagraph
      Row = Data.define(:paragraph, :start)
      Block = Data.define(:key, :line, :offset, :width, :height, :position)

      attr_reader :text, :lines, :width, :height, :inline_placements, :block_placements

      def initialize(text, rows:, blocks:, width:)
        @text, @lines, @inline_placements, @block_placements = text.dup.freeze, [], [], []
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
        hit_test_with_affinity(point).first
      end

      def hit_test_with_affinity(point)
        placements = @inline_placements + @block_placements
        if (overlay = placements.find { |item| Bounds.new(item.x, item.y, item.width, item.height).contains?(point) })
          return [overlay.offset, :downstream]
        end
        return [0, :downstream] if @lines.empty?
        line = @lines.find { |item| point.y < item.y + item.height } || @lines.last
        offset, affinity = line.layout.hit_test(point.x - line.x)
        [[line.start + offset, line.finish].min, affinity]
      end

      def offset_to_point(offset, affinity: :downstream)
        offset = Integer(offset).clamp(0, @text.bytesize)
        placement = @inline_placements.find { |item| item.offset == offset && item.align == :before }
        line = placement ? @lines.fetch(placement.line) : @lines.find { |item| offset <= item.finish } || @lines.last
        Point.new(line.x + line.layout.caret_x((offset - line.start).clamp(0, line.layout.text.bytesize), affinity: affinity), line.y)
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
