# frozen_string_literal: true

module Zaniah
  module UI
    class RichTextSurface < Element
      Run = Data.define(:start, :finish, :layout, :x, :style, :color, :size)
      Line = Data.define(:start, :finish, :x, :y, :width, :height, :ascent, :runs, :paragraph, :first_in_paragraph)

      def initialize(owner)
        super()
        @owner = owner
        @layout_cache = owner.instance_variable_get(:@rich_text_layout_cache) ||
          owner.instance_variable_set(:@rich_text_layout_cache, {})
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
        @writing_mode, @text_orientation = @owner.writing_mode, @owner.text_orientation
        @display_text = @owner.display_text
        @visual_spans = display_spans
        extent = @writing_mode == :vertical_rl ? cx.window.content_size.height : cx.window.content_size.width
        width = resolved_width(@style[@writing_mode == :vertical_rl ? :height : :width], extent)
        @font_size = @style[:font_size] || cx.theme.typography.size_md
        @lines = layout_lines(width, cx)
        embed_elements = @owner.instance_variable_get(:@rich_text_embed_elements) ||
          @owner.instance_variable_set(:@rich_text_embed_elements, {})
        embed_elements.delete_if { |key, _| @owner.embeds.none? { |embed| embed.key == key } }
        @children = @owner.embeds.map { |embed| embed_elements[embed.key] ||= embed.factory.call(cx) }
        raise TypeError, "embed block must return a renderable element" unless @children.all? do |child|
          %i[request_layout prepaint paint].all? { |method| child.respond_to?(method) }
        end
        @children.each { |child| child.send(:parent=, self) }
        nodes = @children.map { |child| child.request_layout(cx) }
        place_embeds(nodes)
        @layout_node = Layout::Node.new(style: @style, children: nodes, measure: lambda do |available, available_height|
          target = @style[@writing_mode == :vertical_rl ? :height : :width].is_a?(Numeric) ? width :
            [@writing_mode == :vertical_rl ? available_height : available, 0].max
          if target != width
            @lines = layout_lines(target, cx)
            place_embeds(nodes)
          end
          [@writing_mode == :vertical_rl ? (@content_width || line_height) : (@lines.map { |line| line.x + line.width }.max || 0),
            @content_height || line_height]
        end)
      end

      def prepaint(bounds, state, cx)
        @bounds = bounds
        super
      end

      def paint(bounds, state, prepaint, cx)
        embeds = @children
        @children = []
        super
        @children = embeds
        selection = @owner.selection.range
        paint_selection(bounds, selection, cx) if @owner.instance_variable_get(:@selectable) && !selection.begin.eql?(selection.end)
        @lines.each do |line|
          para = @owner.paragraph_style_at([line.start, @owner.text.bytesize].min)
          if para[:background]
            if @writing_mode == :vertical_rl
              cx.scene.quad(bounds.x + line.x, bounds.y + line.y, line.height,
                [line.width, 1].max, color: para[:background])
            else
              cx.scene.quad(bounds.x + line.x, bounds.y + line.y, [line.width, 1].max,
                line.height, color: para[:background])
            end
          end
          if para[:quote]
            color = para[:quote] == true ? cx.theme.colors.accent : para[:quote]
            if @writing_mode == :vertical_rl
              cx.scene.quad(bounds.x + line.x, bounds.y + line.y - 8, line.height, 3, color: color)
            else
              cx.scene.quad(bounds.x + line.x - 8, bounds.y + line.y, 3, line.height, color: color)
            end
          end
          line.runs.each do |run|
            next unless run.layout
            if run.style[:background]
              if @writing_mode == :vertical_rl
                cx.scene.quad(bounds.x + line.x, bounds.y + line.y + run.x,
                  line.height, [run.layout.width, 1].max, color: run.style[:background])
              else
                cx.scene.quad(bounds.x + line.x + run.x, bounds.y + line.y,
                  [run.layout.width, 1].max, line.height, color: run.style[:background])
              end
            end
            next unless cx.text_system
            next if @owner.embeds.any? { |embed| embed.offset == run.start && run.finish - run.start == 3 }
            if run.style[:ruby]
              paint_ruby_run(bounds, line, run, cx)
              next
            end
            if @writing_mode == :vertical_rl && run.style[:combine_upright]
              paint_combined_run(bounds, line, run, cx)
              next
            end
            baseline_shift = case run.style[:baseline]
            when :superscript then -run.size * 0.35
            when :subscript then run.size * 0.2
            else 0
            end
            if @writing_mode == :vertical_rl
              cx.text_system.paint_line(cx.scene, run.layout, x: bounds.x + line.x - baseline_shift,
                y: bounds.y + line.y + run.x, color: run.color, text_orientation: @text_orientation)
            else
              cx.text_system.paint_line(cx.scene, run.layout, x: bounds.x + line.x + run.x,
                y: bounds.y + line.y + line.ascent + baseline_shift, color: run.color)
            end
            underline = run.style[:underline] || (run.style[:link] ? :single : nil)
            if underline
              color = run.style[:underline_color] || run.color
              if @writing_mode == :vertical_rl
                x = bounds.x + line.x + line.height - 2
                y = bounds.y + line.y + run.x
                cx.scene.quad(x, y, 1, [run.layout.width, 1].max, color: color)
                cx.scene.quad(x - 3, y, 1, [run.layout.width, 1].max, color: color) if underline == :double
              else
                x = bounds.x + line.x + run.x
                y = bounds.y + line.y + line.ascent + run.size * 0.12 + baseline_shift
                if underline == :wavy
                  (0...run.layout.width.to_i).step(4) do |step|
                    cx.scene.underline(x + step, y + (step % 8 == 0 ? -1 : 1),
                      [4, run.layout.width - step].min, color: color)
                  end
                else
                  cx.scene.underline(x, y, [run.layout.width, 1].max, color: color)
                  cx.scene.underline(x, y + 3, [run.layout.width, 1].max, color: color) if underline == :double
                end
              end
            end
            if run.style[:strikethrough]
              if @writing_mode == :vertical_rl
                cx.scene.quad(bounds.x + line.x + line.height / 2.0,
                  bounds.y + line.y + run.x, 1, [run.layout.width, 1].max, color: run.color)
              else
                cx.scene.underline(bounds.x + line.x + run.x,
                  bounds.y + line.y + line.ascent - run.size * 0.35 + baseline_shift,
                  [run.layout.width, 1].max, color: run.color)
              end
            end
          end
          paint_list_marker(bounds, line, cx)
        end
        paint_embeds = lambda do
          embeds.each do |embed|
            embed.paint(embed.layout_node.bounds, nil, nil, cx) unless embed.layout_node.style[:display] == :none
          end
        end
        @style[:overflow] == :visible ? paint_embeds.call : cx.scene.clip(bounds, &paint_embeds)
        paint_composition(bounds, cx) if @owner.buffer.composition
        paint_caret(bounds, cx) if @owner.editable? && @owner.selection.collapsed? && cx.dispatcher.focused == @focus_handle
        cx.window.text_runs.concat(@lines.flat_map do |line|
          line.runs.map do |run|
            x = bounds.x + line.x + (@writing_mode == :vertical_rl ? 0 : run.x)
            y = bounds.y + line.y + (@writing_mode == :vertical_rl ? run.x : 0)
            [x, y, @display_text.byteslice(run.start...run.finish), run.color]
          end
        end) if cx.window.respond_to?(:text_runs)
      ensure
        @children = embeds if embeds
      end

      def hit_test(point)
        return 0 if @lines.empty?
        line = if @writing_mode == :vertical_rl
          @lines.find { |item| point.x >= item.x && point.x < item.x + item.height } ||
            (point.x >= @lines.first.x + @lines.first.height ? @lines.first : @lines.last)
        else
          @lines.find { |item| point.y < item.y + item.height } || @lines.last
        end
        return 0 unless line
        inline = @writing_mode == :vertical_rl ? point.y - line.y : point.x - line.x
        run = line.runs.find { |item| inline < item.x + item.layout&.width.to_f } || line.runs.last
        return line.start unless run
        run.start + (run.layout ? run.layout.index_for_x(inline - run.x) : 0).clamp(0, run.finish - run.start)
      end

      private

      def place_embeds(nodes)
        @owner.embeds.zip(nodes).each do |embed, node|
          line = @lines.find { |item| embed.offset.between?(item.start, item.finish) }
          run = line&.runs&.find { |item| item.start == embed.offset }
          next unless line && run
          if @writing_mode == :vertical_rl
            node.style = node.style.merge(position: :absolute,
              left: line.x + (line.height - embed.width) / 2.0,
              top: line.y + run.x, width: embed.width, height: embed.height)
          else
            node.style = node.style.merge(position: :absolute, left: line.x + run.x,
              top: line.y + (line.height - embed.height) / 2.0, width: embed.width, height: embed.height)
          end
        end
      end

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

      # Reuse complete paragraphs before an append; only the final paragraph
      # can change. Fragment layouts are cached separately across surfaces.
      def layout_lines(width, cx)
        cache = @owner.instance_variable_get(:@rich_text_lines_cache)
        start = @owner.instance_variable_get(:@append_start)
        start = nil if @writing_mode == :vertical_rl
        if cache && start && cache[:width] == width && cache[:size] == @font_size &&
            cache[:theme].equal?(cx.theme) && @display_text.start_with?(cache[:text])
          reused = cache[:lines].take_while { |line| line.start < start }
          old_first = cache[:lines].find { |line| line.start >= start }
          paragraph_index = @display_text.byteslice(0...start).count("\n")
          before = @owner.paragraph_styles.fetch(paragraph_index, {})[:spacing_before].to_f
          y = old_first ? old_first.y - before : 0.0
        else
          start, reused, paragraph_index, y = 0, [], 0, 0.0
        end
        atomic = @visual_spans.filter_map do |first, finish, style|
          (first - start)...(finish - start) if (style[:ruby] || style[:combine_upright]) && first >= start
        end
        breaker = TextSystem::LineBreaker.new(@display_text.byteslice(start..), wrap: :word,
          kinsoku: :push, atomic_ranges: atomic)
        ranges = breaker.ranges_with_offsets(width) do |_candidate, first, finish|
          fragments(first + start, finish + start).sum do |from, to, style|
            fragment_layout(from, to, style, cx).width
          end
        end.map { |range| (range.begin + start)...(range.end + start) }
        fresh = ranges.each_with_index.map do |range, index|
          paragraph_index += 1 if index.positive? && @display_text.getbyte(ranges[index - 1].end) == 10
          para = @owner.paragraph_styles.fetch(paragraph_index, {})
          indent = Integer(para[:level] || 0) * 16 + (para[:list] && para[:list] != :none ? 20 : 0) +
            (para[:indent] || 0).to_f + (para[:quote] ? 12 : 0)
          parts, direction = visual_parts(range, cx)
          direction = :ltr if @writing_mode == :vertical_rl
          parts = parts.map do |first, finish, style, run_direction|
            Run.new(first, finish, fragment_layout(first, finish, style, cx, direction: run_direction), 0, style,
              style[:color] || cx.theme.colors.text, style[:size] || @font_size)
          end
          width_used = parts.sum { |part| part.layout.width }
          available = [width - indent, 0].max
          next_range = ranges[index + 1]
          next_paragraph = next_range && (paragraph_index + (@display_text.getbyte(range.end) == 10 ? 1 : 0))
          if para[:align] == :justify && direction == :ltr && next_range && next_paragraph == paragraph_index
            parts = justified_parts(parts, range, available, width_used)
            width_used = available
          end
          align = para[:align] || :start
          offset = case align
          when :center then indent + [(available - width_used) / 2.0, 0].max
          when :end then direction == :rtl ? indent : indent + [available - width_used, 0].max
          else direction == :rtl ? indent + [available - width_used, 0].max : indent
          end
          x = 0.0
          runs = parts.map do |part|
            Run.new(part.start, part.finish, part.layout, x, part.style, part.color, part.size).tap { x += part.layout.width }
          end
          ascent = runs.map { |run| run.layout&.ascent || run.size * 0.8 }.max || @font_size * 0.8
          descent = runs.map { |run| run.layout&.descent || run.size * 0.2 }.max || @font_size * 0.2
          height = [line_height, ascent + descent].max
          first_in_paragraph = index.zero? || @display_text.getbyte(ranges[index - 1].end) == 10
          y += (para[:spacing_before] || 0).to_f if first_in_paragraph
          item = Line.new(range.begin, range.end, offset, y, width_used, height, ascent, runs, paragraph_index,
            first_in_paragraph)
          y += height
          y += (para[:spacing_after] || 0).to_f if !next_range || next_paragraph != paragraph_index
          item
        end
        lines = reused + fresh
        if @writing_mode == :vertical_rl
          @content_width = y
          used = 0.0
          lines = lines.map do |line|
            used += line.height
            line.with(x: y - used, y: line.x)
          end
          @content_height = [lines.map { |line| line.y + line.width }.max || 0, width].min
        else
          @content_width = nil
          @content_height = y
        end
        @owner.instance_variable_set(:@rich_text_lines_cache,
          {text: @display_text.dup.freeze, width: width, size: @font_size,
            theme: cx.theme, lines: lines})
        @owner.instance_variable_set(:@append_start, nil)
        lines
      end

      def visual_parts(range, cx)
        content = @display_text.byteslice(range)
        @bidi_rows ||= begin
          byte = 0
          rows = @display_text.empty? ? [""] : @display_text.split("\n", -1)
          rows.map do |row|
            item = [byte, byte + row.bytesize, row, nil]
            byte += row.bytesize + 1
            item
          end
        end
        row = @bidi_rows.bsearch { |item| item[1] >= range.begin } || @bidi_rows.last
        if row[2].ascii_only?
          return [fragments(range.begin, range.end).map { |from, to, style| [from, to, style, :ltr] }, :ltr]
        end
        row[3] ||= Unicode::Bidi.resolve(row[2])
        first = range.begin == row[0] ? 0 : row[2].byteslice(0...(range.begin - row[0])).length
        bidi = Unicode::Bidi.line_result(row[3], row[2], first, first + content.length)
        bytes = [0]
        content.each_char { |char| bytes << bytes.last + char.bytesize }
        groups = []
        bidi.visual_order.each do |index|
          at = range.begin + bytes[index]
          style, level = style_at_display(at), bidi.levels[index]
          if groups.last && groups.last[0] == style && groups.last[1] == level && (groups.last[3] - index).abs == 1
            groups.last[3] = index
          else
            groups << [style, level, index, index]
          end
        end
        parts = groups.map do |style, level, first, last|
          lower, upper = [first, last].minmax
          [range.begin + bytes[lower], range.begin + bytes[upper + 1], style, level.odd? ? :rtl : :ltr]
        end
        [split_embeds(parts), bidi.direction]
      end

      def split_embeds(parts)
        parts.flat_map do |first, finish, style, direction|
          boundaries = [first, finish]
          @owner.embeds.each do |embed|
            boundaries.concat([embed.offset, embed.offset + 3]) if embed.offset >= first && embed.offset + 3 <= finish
          end
          slices = boundaries.uniq.sort.each_cons(2).map { |from, to| [from, to, style, direction] }
          direction == :rtl ? slices.reverse : slices
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
          visual_carets = layout.visual_carets&.map do |byte, affinity, x|
            [byte, affinity, x + shift.call(part.start + byte - range.begin)]
          end&.freeze
          adjusted = TextSystem::LineLayout.new(layout.text, glyphs, layout.width + shift.call(part.finish - range.begin),
            layout.ascent, layout.descent, layout.size, carets, visual_carets, layout.writing_mode)
          Run.new(part.start, part.finish, adjusted, part.x, part.style, part.color, part.size)
        end
      end

      def fragments(first, finish)
        return [] if first == finish
        boundaries = [first, finish]
        @owner.embeds.each do |embed|
          boundaries << embed.offset if embed.offset > first && embed.offset < finish
          boundaries << embed.offset + 3 if embed.offset + 3 > first && embed.offset + 3 < finish
        end
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

      def fragment_layout(first, finish, style, cx, direction: :auto)
        text = @display_text.byteslice(first...finish)
        if text == "\uFFFC" && (embed = @owner.embeds.find { |item| item.offset == first })
          extent = @writing_mode == :vertical_rl ? embed.height : embed.width
          cross = @writing_mode == :vertical_rl ? embed.width : embed.height
          return TextSystem::LineLayout.new(text, [].freeze, extent, cross, 0,
            cross, [[0, 0.0], [text.bytesize, extent]].freeze, nil, @writing_mode)
        end
        size = style[:size] || @font_size
        size *= 0.75 if %i[superscript subscript].include?(style[:baseline])
        font = font_for(style, cx)
        key = [text, size, font&.object_id, direction, style[:letter_spacing],
          style[:ruby], style[:combine_upright], @writing_mode]
        @layout_cache[key] ||= begin
          line = if @writing_mode == :vertical_rl && style[:combine_upright]
            combined_layout(text, size, font, cx)
          elsif cx.text_system
            params = cx.text_system.method(:layout_line).parameters
            kwargs = {font: font, size: size}
            kwargs[:direction] = direction if params.include?([:key, :direction]) || params.any? { |kind, _| kind == :keyrest }
            kwargs[:writing_mode] = @writing_mode if params.include?([:key, :writing_mode]) || params.any? { |kind, _| kind == :keyrest }
            result = cx.text_system.layout_line(text, **kwargs)
            @writing_mode == :vertical_rl && result.writing_mode != :vertical_rl ? result.with(writing_mode: :vertical_rl) : result
          else
            approximate_layout(text, size)
          end
          line = space_layout(line, style[:letter_spacing]) if style[:letter_spacing]
          if style[:ruby]
            ruby = annotation_layout(style[:ruby], size, font, cx)
            extent = [line.width, ruby.width].max
            TextSystem::LineLayout.new(text, [].freeze, extent,
              line.ascent + ruby.size * 1.2, line.descent, line.size,
              [[0, 0.0], [text.bytesize, extent]].freeze, nil, @writing_mode)
          elsif @writing_mode == :vertical_rl && style[:combine_upright]
            TextSystem::LineLayout.new(text, [].freeze, size,
              size * 0.8, size * 0.2, size,
              [[0, 0.0], [text.bytesize, size]].freeze, nil, @writing_mode)
          else
            line
          end
        end
      end

      def combined_layout(text, size, font, cx)
        key = [:combined, text, size, font&.object_id]
        @layout_cache[key] ||= begin
          layout = if cx.text_system
            cx.text_system.layout_line(text, font: font, size: size)
          else
            approximate_layout(text, size)
          end
          if layout.width > size && layout.width.positive?
            reduced = size * size / layout.width
            layout = cx.text_system ? cx.text_system.layout_line(text, font: font, size: reduced) : approximate_layout(text, reduced)
          end
          layout
        end
      end

      def annotation_layout(text, parent_size, font, cx)
        size = parent_size * 0.5
        key = [:ruby_annotation, text, size, font&.object_id, @writing_mode]
        @layout_cache[key] ||= if cx.text_system
          params = cx.text_system.method(:layout_line).parameters
          kwargs = {font: font, size: size}
          kwargs[:writing_mode] = @writing_mode if params.include?([:key, :writing_mode]) || params.any? { |kind, _| kind == :keyrest }
          result = cx.text_system.layout_line(text, **kwargs)
          @writing_mode == :vertical_rl && result.writing_mode != :vertical_rl ? result.with(writing_mode: :vertical_rl) : result
        else
          approximate_layout(text, size)
        end
      end

      def paint_ruby_run(bounds, line, run, cx)
        base_style = run.style.reject { |key, _| key == :ruby }
        base = fragment_layout(run.start, run.finish, base_style, cx)
        ruby = annotation_layout(run.style[:ruby], run.size, font_for(run.style, cx), cx)
        if @writing_mode == :vertical_rl
          base_x = bounds.x + line.x
          ruby_x = base_x + [base.ascent + base.descent, run.size].max
          base_y = bounds.y + line.y + run.x + (run.layout.width - base.width) / 2.0
          ruby_y = bounds.y + line.y + run.x + (run.layout.width - ruby.width) / 2.0
          cx.text_system.paint_line(cx.scene, base, x: base_x, y: base_y,
            color: run.color, text_orientation: @text_orientation)
          cx.text_system.paint_line(cx.scene, ruby, x: ruby_x, y: ruby_y,
            color: run.color, text_orientation: :upright)
        else
          base_x = bounds.x + line.x + run.x + (run.layout.width - base.width) / 2.0
          ruby_x = bounds.x + line.x + run.x + (run.layout.width - ruby.width) / 2.0
          cx.text_system.paint_line(cx.scene, base, x: base_x,
            y: bounds.y + line.y + line.ascent, color: run.color)
          cx.text_system.paint_line(cx.scene, ruby, x: ruby_x,
            y: bounds.y + line.y + ruby.ascent, color: run.color)
        end
      end

      def paint_combined_run(bounds, line, run, cx)
        layout = combined_layout(@display_text.byteslice(run.start...run.finish), run.size,
          font_for(run.style, cx), cx)
        x = bounds.x + line.x + (line.height - layout.width) / 2.0
        y = bounds.y + line.y + run.x + (run.layout.width - layout.ascent - layout.descent) / 2.0 + layout.ascent
        cx.text_system.paint_line(cx.scene, layout, x: x, y: y, color: run.color)
      end

      def space_layout(line, amount)
        return line if line.carets.length < 2
        shifted = line.carets.each_with_index.map { |(byte, x), i| [byte, x + i * amount] }
        glyphs = line.glyphs.map do |glyph|
          index = line.carets.bsearch_index { |byte, _| byte >= glyph.start } || 0
          glyph.with(x: glyph.x + index * amount)
        end
        visual = line.visual_carets&.map do |byte, affinity, x|
          index = line.carets.bsearch_index { |at, _| at >= byte } || 0
          [byte, affinity, x + index * amount]
        end
        TextSystem::LineLayout.new(line.text, glyphs.freeze, line.width + (line.carets.length - 1) * amount,
          line.ascent, line.descent, line.size, shifted.freeze, visual&.freeze, line.writing_mode)
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
        TextSystem::LineLayout.new(text, [].freeze, x, size * 0.8, size * 0.2, size, carets, nil, @writing_mode)
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
            run.layout.selection_rects((from - run.start)...(to - run.start)).each do |rect|
              if @writing_mode == :vertical_rl
                cx.scene.quad(bounds.x + line.x, bounds.y + line.y + run.x + rect.x,
                  line.height, [rect.width, 1].max, color: cx.theme.colors.selection)
              else
                cx.scene.quad(bounds.x + line.x + run.x + rect.x, bounds.y + line.y,
                  [rect.width, 1].max, line.height, color: cx.theme.colors.selection)
              end
            end
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
        if @writing_mode == :vertical_rl
          cx.text_system&.paint_line(cx.scene, layout, x: bounds.x + line.x,
            y: bounds.y + line.y - 18 + layout.ascent, color: cx.theme.colors.text)
        else
          cx.text_system&.paint_line(cx.scene, layout, x: bounds.x + line.x - 18,
            y: bounds.y + line.y + line.ascent, color: cx.theme.colors.text)
        end
      end

      def paint_caret(bounds, cx)
        offset = @owner.selection.range.begin + (@owner.buffer.composition&.selection&.first || 0)
        line = @lines.find { |item| offset.between?(item.start, item.finish) } || @lines.last
        return unless line
        run = line.runs.find { |item| offset.between?(item.start, item.finish) } || line.runs.last
        inline = run ? run.x + (run.layout ? run.layout.x_for_index((offset - run.start).clamp(0, run.finish - run.start)) : 0) : 0
        ascent, descent = run&.layout ? [run.layout.ascent, run.layout.descent] : [@font_size * 0.8, @font_size * 0.2]
        y, height = line.y + line.ascent - ascent, ascent + descent
        color = run&.color || cx.theme.colors.text
        if @writing_mode == :vertical_rl
          cx.scene.layer(Scene::LAYER_FOCUS_RING) do
            cx.scene.quad(bounds.x + line.x, bounds.y + line.y + inline, line.height, 1, color: color)
          end
          cx.window.ime_state = Bounds.new(bounds.x + line.x, bounds.y + line.y + inline, line.height, 1)
        else
          x = line.x + inline
          cx.scene.layer(Scene::LAYER_FOCUS_RING) { cx.scene.quad(bounds.x + x, bounds.y + y, 1, height, color: color) }
          cx.window.ime_state = Bounds.new(bounds.x + x, bounds.y + y, 1, height)
        end
      end

      def paint_composition(bounds, cx)
        offset = @owner.selection.range.begin
        finish = offset + @owner.buffer.composition.text.bytesize
        first, last = point_for(offset), point_for(finish)
        cx.scene.layer(Scene::LAYER_FOCUS_RING) do
          if @writing_mode == :vertical_rl
            cx.scene.quad(bounds.x + first.x + @font_size * 1.25, bounds.y + [first.y, last.y].min,
              1, [(last.y - first.y).abs, 1].max, color: cx.theme.colors.text)
          else
            cx.scene.underline(bounds.x + [first.x, last.x].min, bounds.y + first.y + @font_size * 1.25,
              [(last.x - first.x).abs, 1].max, color: cx.theme.colors.text)
          end
        end
      end

      def point_for(offset)
        line = @lines.find { |item| offset.between?(item.start, item.finish) } || @lines.last
        return Point.new(0, 0) unless line
        run = line.runs.find { |item| offset.between?(item.start, item.finish) } || line.runs.last
        inline = run ? run.x + run.layout.x_for_index((offset - run.start).clamp(0, run.finish - run.start)) : 0
        @writing_mode == :vertical_rl ? Point.new(line.x, line.y + inline) : Point.new(line.x + inline, line.y)
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
