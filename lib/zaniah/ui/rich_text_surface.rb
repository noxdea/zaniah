# frozen_string_literal: true

module Zaniah
  module UI
    class RichTextSurface < Element
      Run = Data.define(:start, :finish, :layout, :x, :style, :color, :size)
      Line = Data.define(:start, :finish, :x, :y, :width, :height, :ascent, :runs, :paragraph, :first_in_paragraph)

      def initialize(owner)
        super()
        @owner = owner
        @layout_cache = {}
        return unless owner.instance_variable_get(:@selectable) || owner.editable?

        if owner.instance_variable_get(:@selectable)
          on_mouse_down { |event, _cx| begin_selection(event) }
          on_drag { |event, _cx| extend_selection(event) }
        end
        focusable(context: {in_text_field: true, in_text: !owner.editable?, multiline: true},
          validate: ->(action) { owner.validate_text_action(action) }) do |action|
          owner.text_action(action)
        end
        @focus_handle.on_input = ->(event) { owner.input(event) }
      end

      def request_layout(cx)
        @cx = cx
        @display_text = @owner.display_text
        @visual_spans = display_spans
        width = resolved_width(@style[:width], cx.window.content_size.width)
        @font_size = @style[:font_size] || cx.theme.typography.size_md
        @lines = layout_lines(width, cx)
        @layout_node = Layout::Node.new(style: @style, measure: lambda do |available, _height|
          target = @style[:width].is_a?(Numeric) ? width : [available, 0].max
          @lines = layout_lines(target, cx) if target != width
          [@lines.map { |line| line.x + line.width }.max || 0, @lines.last ? @lines.last.y + @lines.last.height : line_height]
        end)
      end

      def prepaint(bounds, state, cx)
        @bounds = bounds
        super
      end

      def paint(bounds, state, prepaint, cx)
        super
        selection = @owner.selection.range
        paint_selection(bounds, selection, cx) if @owner.instance_variable_get(:@selectable) && !selection.begin.eql?(selection.end)
        @lines.each do |line|
          line.runs.each do |run|
            next unless run.layout && cx.text_system
            cx.text_system.paint_line(cx.scene, run.layout, x: bounds.x + line.x + run.x,
              y: bounds.y + line.y + line.ascent, color: run.color)
            if run.style[:link]
              cx.scene.underline(bounds.x + line.x + run.x, bounds.y + line.y + line.ascent + run.size,
                [run.layout.width, 1].max, color: run.color)
            end
          end
          paint_list_marker(bounds, line, cx)
        end
        paint_composition(bounds, cx) if @owner.buffer.composition
        paint_caret(bounds, cx) if @owner.editable? && @owner.selection.collapsed? && cx.dispatcher.focused == @focus_handle
        cx.window.text_runs.concat(@lines.flat_map do |line|
          line.runs.map { |run| [bounds.x + line.x + run.x, bounds.y + line.y, @display_text.byteslice(run.start...run.finish), run.color] }
        end) if cx.window.respond_to?(:text_runs)
      end

      def hit_test(point)
        line = @lines.find { |item| point.y < item.y + item.height } || @lines.last
        return 0 unless line
        run = line.runs.find { |item| point.x < line.x + item.x + item.layout&.width.to_f } || line.runs.last
        return line.start unless run
        run.start + (run.layout ? run.layout.index_for_x(point.x - line.x - run.x) : 0).clamp(0, run.finish - run.start)
      end

      private

      def resolved_width(value, available)
        value = value.resolve(available) if value.is_a?(Length)
        value.is_a?(Numeric) ? [value, 0].max : available
      end

      def display_spans
        spans = @owner.spans.map { |span| [span.start, span.finish, span.style] }
        composition = @owner.buffer.composition
        return spans unless composition
        range = @owner.selection.range
        at, delta = range.begin, composition.text.bytesize - range.size
        style = @owner.style_at(at)
        spans = spans.flat_map do |first, finish, value|
          if finish <= range.begin
            [[first, finish, value]]
          elsif first >= range.end
            [[first + delta, finish + delta, value]]
          else
            pieces = []
            pieces << [first, range.begin, value] if first < range.begin
            pieces << [range.begin + composition.text.bytesize, finish + delta, value] if finish > range.end
            pieces
          end
        end
        spans << [at, at + composition.text.bytesize, style] unless style.empty?
        spans.sort_by(&:first)
      end

      # ponytail: each candidate prefix is shaped during line breaking; long unbroken paragraphs are quadratic. Cache wins for repeated fragments; add a streaming breaker if profiling proves this hot.
      def layout_lines(width, cx)
        breaker = TextSystem::LineBreaker.new(@display_text, wrap: :word, kinsoku: :push)
        ranges = breaker.ranges_with_offsets(width) do |_candidate, first, finish|
          fragments(first, finish).sum { |from, to, style| fragment_layout(from, to, style, cx).width }
        end
        y = 0.0
        ranges.each_with_index.map do |range, index|
          paragraph_index = @display_text.byteslice(0...range.begin).count("\n")
          para = @owner.paragraph_style_at([range.begin, @owner.text.bytesize].min)
          indent = Integer(para[:level] || 0) * 16 + (para[:list] && para[:list] != :none ? 20 : 0)
          parts = fragments(range.begin, range.end).map do |first, finish, style|
            Run.new(first, finish, fragment_layout(first, finish, style, cx), 0, style,
              style[:color] || cx.theme.colors.text, style[:size] || @font_size)
          end
          width_used = parts.sum { |part| part.layout.width }
          available = [width - indent, 0].max
          next_range = ranges[index + 1]
          next_paragraph = next_range && @display_text.byteslice(0...next_range.begin).count("\n")
          if para[:align] == :justify && next_range && next_paragraph == paragraph_index
            parts = justified_parts(parts, range, available, width_used)
            width_used = available
          end
          align = para[:align] || :start
          offset = case align
          when :center then indent + [(available - width_used) / 2.0, 0].max
          when :end then indent + [available - width_used, 0].max
          else indent
          end
          x = 0.0
          runs = parts.map do |part|
            Run.new(part.start, part.finish, part.layout, x, part.style, part.color, part.size).tap { x += part.layout.width }
          end
          ascent = runs.map { |run| run.layout&.ascent || run.size * 0.8 }.max || @font_size * 0.8
          descent = runs.map { |run| run.layout&.descent || run.size * 0.2 }.max || @font_size * 0.2
          height = [line_height, ascent + descent].max
          previous_break = @display_text.byteslice(0...range.begin).rindex("\n")
          item = Line.new(range.begin, range.end, offset, y, width_used, height, ascent, runs, paragraph_index,
            range.begin == (previous_break ? previous_break + 1 : 0))
          y += height
          item
        end
      end

      def justified_parts(parts, range, available, line_width)
        return parts if available <= line_width
        spaces = []
        @display_text.byteslice(range).to_enum(:scan, /\s+/).each { spaces << Regexp.last_match.end(0) }
        return parts if spaces.empty?
        extra = (available - line_width) / spaces.length
        parts.map do |part|
          layout = part.layout
          shift = ->(byte) { spaces.count { |finish| finish <= byte } * extra }
          carets = layout.carets.map { |byte, x| [byte, x + shift.call(part.start + byte - range.begin)] }.freeze
          glyphs = layout.glyphs.map do |glyph|
            TextSystem::Glyph.new(glyph.font, glyph.id, glyph.start, glyph.finish,
              glyph.x + shift.call(part.start + glyph.start - range.begin), glyph.advance)
          end.freeze
          adjusted = TextSystem::LineLayout.new(layout.text, glyphs, layout.width + shift.call(part.finish - range.begin),
            layout.ascent, layout.descent, layout.size, carets)
          Run.new(part.start, part.finish, adjusted, part.x, part.style, part.color, part.size)
        end
      end

      def fragments(first, finish)
        return [] if first == finish
        boundaries = [first, finish]
        @visual_spans.each do |from, to, _style|
          boundaries << from if from > first && from < finish
          boundaries << to if to > first && to < finish
        end
        boundaries.uniq.sort.each_cons(2).map { |from, to| [from, to, style_at_display(from)] }
      end

      def style_at_display(offset)
        span = @visual_spans.find { |first, finish, _| offset >= first && offset < finish }
        span ? span[2] : {}
      end

      def fragment_layout(first, finish, style, cx)
        text = @display_text.byteslice(first...finish)
        size = style[:size] || @font_size
        font = font_for(style, cx)
        key = [text, size, font&.object_id]
        @layout_cache[key] ||= cx.text_system&.layout_line(text, font: font, size: size) || approximate_layout(text, size)
      end

      def approximate_layout(text, size)
        byte = 0
        x = 0.0
        carets = [[0, 0.0]]
        text.grapheme_clusters.each do |cluster|
          byte += cluster.bytesize
          x += Unicode.width(cluster) * size * 0.6
          carets << [byte, x]
        end
        TextSystem::LineLayout.new(text, [].freeze, x, size * 0.8, size * 0.2, size, carets)
      end

      def font_for(style, cx)
        return style[:font] if style[:font]
        return unless cx.text_system
        font = cx.text_system.respond_to?(:font) ? cx.text_system.font : nil
        return font unless style[:bold] || style[:italic]
        database = cx.text_system.respond_to?(:font_db) ? cx.text_system.font_db : nil
        database&.find(family: font&.family, weight: style[:bold] ? 700 : 400,
          style: style[:italic] ? :italic : :normal) || font
      rescue StandardError
        font
      end

      def line_height = @font_size * 1.4

      def paint_selection(bounds, range, cx)
        @lines.each do |line|
          first, finish = [range.begin, line.start].max, [range.end, line.finish].min
          next if finish <= first
          line.runs.each do |run|
            from, to = [first, run.start].max, [finish, run.finish].min
            next if to <= from || !run.layout
            left = run.layout.x_for_index(from - run.start)
            right = run.layout.x_for_index(to - run.start)
            cx.scene.quad(bounds.x + line.x + run.x + left, bounds.y + line.y,
              [right - left, 1].max, line.height, color: cx.theme.colors.selection)
          end
        end
      end

      def paint_list_marker(bounds, line, cx)
        return unless line.first_in_paragraph
        para = @owner.paragraph_style_at([line.start, @owner.text.bytesize].min)
        marker = case para[:list]
        when :bullet then "•"
        when :ordered then "#{line.paragraph + 1}."
        else return
        end
        layout = cx.text_system&.layout_line(marker, size: @font_size)
        cx.text_system&.paint_line(cx.scene, layout, x: bounds.x + line.x - 18,
          y: bounds.y + line.y + line.ascent, color: cx.theme.colors.text)
      end

      def paint_caret(bounds, cx)
        offset = @owner.selection.range.begin + (@owner.buffer.composition&.selection&.first || 0)
        line = @lines.find { |item| offset.between?(item.start, item.finish) } || @lines.last
        return unless line
        run = line.runs.find { |item| offset.between?(item.start, item.finish) } || line.runs.last
        x = line.x + (run ? run.x + (run.layout ? run.layout.x_for_index((offset - run.start).clamp(0, run.finish - run.start)) : 0) : 0)
        ascent, descent = run&.layout ? [run.layout.ascent, run.layout.descent] : [@font_size * 0.8, @font_size * 0.2]
        y, height = line.y + line.ascent - ascent, ascent + descent
        color = run&.color || cx.theme.colors.text
        cx.scene.layer(Scene::LAYER_FOCUS_RING) { cx.scene.quad(bounds.x + x, bounds.y + y, 1, height, color: color) }
        cx.window.ime_state = Bounds.new(bounds.x + x, bounds.y + y, 1, height)
      end

      def paint_composition(bounds, cx)
        offset = @owner.selection.range.begin
        finish = offset + @owner.buffer.composition.text.bytesize
        first, last = point_for(offset), point_for(finish)
        cx.scene.layer(Scene::LAYER_FOCUS_RING) do
          cx.scene.underline(bounds.x + first.x, bounds.y + first.y + @font_size * 1.25,
            [last.x - first.x, 1].max, color: cx.theme.colors.text)
        end
      end

      def point_for(offset)
        line = @lines.find { |item| offset.between?(item.start, item.finish) } || @lines.last
        return Point.new(0, 0) unless line
        run = line.runs.find { |item| offset.between?(item.start, item.finish) } || line.runs.last
        x = line.x + (run ? run.x + run.layout.x_for_index((offset - run.start).clamp(0, run.finish - run.start)) : 0)
        Point.new(x, line.y)
      end

      def begin_selection(event)
        offset = hit_test(Point.new(event.position.x - @bounds.x, event.position.y - @bounds.y))
        @owner.selection = event.click_count == 2 ? word_selection(offset) : TextSelection.new(offset)
        @owner.instance_variable_get(:@cx)&.window&.request_frame
      end

      def extend_selection(event)
        return unless @owner.selection
        offset = hit_test(Point.new(event.position.x - @bounds.x, event.position.y - @bounds.y))
        @owner.selection = TextSelection.new(@owner.selection.anchor, offset)
        @owner.instance_variable_get(:@cx)&.window&.request_frame
      end

      def word_selection(offset)
        range = Unicode.word_range_at(@owner.text, [offset, @owner.text.bytesize].min)
        TextSelection.new(range.begin, range.end)
      end
    end
  end
end
