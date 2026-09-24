# frozen_string_literal: true

module Zaniah
  module UI
    class CodeEditor
      # Only visible logical lines are shaped. HeightIndex keeps wrapped rows
      # addressable without constructing an Element for every source line.
      class Surface < Element
        Row = Data.define(:index, :paragraph, :top, :text)
        attr_reader :visible_range, :scroll_state, :heights

        def initialize(owner)
          super()
          @owner = owner
          @scroll_state = ScrollState.new(axis: :vertical)
          @visible_range = 0...0
          style(overflow: :hidden)
          focusable(context: {in_text_field: true, in_code_editor: true, multiline: true},
            validate: ->(action) { owner.validate_text_action(action) }) { |action| owner.text_action(action) }
          @focus_handle.on_input = ->(event) { owner.input(event) }
          on_scroll_wheel do |event, cx|
            @scroll_state.scroll_by(event.delta.y)
            cx.window.request_frame
          end
          on_mouse_down do |event, cx|
            @owner.selection = TextSelection.new(hit_test(local_point(event.position)))
            cx.window.request_frame
          end
          on_drag do |event, cx|
            @owner.selection = TextSelection.new(@owner.selection.anchor, hit_test(local_point(event.position)))
            cx.window.request_frame
          end
        end

        def scroll_y = @scroll_state.offset.y
        def scroll_y=(value)
          @scroll_state.scroll_to(value)
          value
        end

        def request_layout(cx)
          @cx = cx
          @size = cx.theme.typography.size_sm
          @line_height = @size * 1.4
          width = dimension(:width, cx.window.content_size.width)
          height = dimension(:height, cx.window.content_size.height)
          @gutter = @owner.line_numbers? ? 48 : 0
          count = @owner.buffer.line_count
          if !@heights || @heights.count != count || @revision != @owner.revision || @width != width
            @heights = List::HeightIndex.new(count, @line_height)
            @revision = @owner.revision
          end
          @width = width
          @viewport_height = height
          @scroll_state.update(content_size: Size.new(width, @heights.total), viewport_size: Size.new(width, height))
          first = [@heights.index_at(scroll_y) - 2, 0].max
          last = [@heights.index_at(scroll_y + height) + 3, count].min
          @visible_range = first...last
          paragraphs = @visible_range.map do |index|
            text = @owner.buffer.line(index)
            paragraph = TextSystem::Paragraph.new(text, width: [width - @gutter, 0].max,
              size: @size, line_height: @line_height, wrap: @owner.wrap? ? :anywhere : :none,
              typesetter: cx.text_system)
            @heights.update(index, [paragraph.height, @line_height].max)
            [index, paragraph, text]
          end
          @scroll_state.update(content_size: Size.new(width, @heights.total), viewport_size: Size.new(width, height))
          @rows = paragraphs.map do |index, paragraph, text|
            Row.new(index, paragraph, @heights.prefix(index) - scroll_y, text)
          end
          @layout_node = Layout::Node.new(style: @style,
            measure: ->(_available, _height) { [width, height] })
        end

        def prepaint(bounds, state, cx)
          @bounds = bounds
          super
        end

        def paint(bounds, state, prepaint, cx)
          super
          return unless @rows
          if @gutter.positive?
            cx.scene.quad(bounds.x, bounds.y, @gutter, bounds.height,
              color: cx.theme.colors.surface)
          end
          selection = @owner.selection.range
          @rows.each do |row|
            base = @owner.buffer.line_start(row.index)
            first = [selection.begin - base, 0].max
            finish = [selection.end - base, row.text.bytesize].min
            if finish > first
              row.paragraph.selection_rects(first...finish).each do |rect|
                cx.scene.quad(bounds.x + @gutter + rect.x,
                  bounds.y + row.top + rect.y, [rect.width, 1].max, rect.height,
                  color: cx.theme.colors.selection)
              end
            end
            next unless cx.text_system
            if @gutter.positive?
              number = cx.text_system.layout_line((row.index + 1).to_s.encode(Encoding::UTF_8), size: @size)
              cx.text_system.paint_line(cx.scene, number, x: bounds.x + @gutter - 8 - number.width,
                y: bounds.y + row.top + number.ascent, color: cx.theme.colors.text_muted)
            end
            spans = token_spans(row, cx)
            row.paragraph.lines.each do |line|
              local = spans.filter_map do |start, finish, color|
                from, to = [start, line.start].max, [finish, line.finish].min
                [from - line.start, to - line.start, color] if to > from
              end
              cx.text_system.paint_line(cx.scene, line.layout,
                x: bounds.x + @gutter + line.x,
                y: bounds.y + row.top + line.y + line.layout.ascent,
                color: cx.theme.syntax.text, spans: local)
            end
          end
          paint_caret(bounds, cx) if cx.dispatcher.focused == @focus_handle
        end

        def hit_test(point)
          return 0 if @owner.buffer.line_count.zero?
          index = [@heights.index_at(point.y + scroll_y), @owner.buffer.line_count - 1].min
          row = @rows.find { |item| item.index == index }
          unless row
            text = @owner.buffer.line(index)
            paragraph = TextSystem::Paragraph.new(text, width: [@width - @gutter, 0].max,
              size: @size, line_height: @line_height, wrap: @owner.wrap? ? :anywhere : :none,
              typesetter: @cx.text_system)
            row = Row.new(index, paragraph, @heights.prefix(index) - scroll_y, text)
          end
          local = Point.new(point.x - @gutter, point.y - row.top)
          @owner.buffer.line_start(index) + row.paragraph.hit_test(local)
        end

        def ensure_caret_visible
          return unless @heights
          index = @owner.buffer.line_of(@owner.selection.head)
          @scroll_state.scroll_rect(Bounds.new(0, @heights.prefix(index), 1, @heights[index]), align: :nearest)
        end

        private

        def dimension(name, available)
          value = @style[name]
          value = value.resolve(available) if value.is_a?(Length)
          value.is_a?(Numeric) ? [value.to_f, 0].max : available.to_f
        end

        def local_point(point) = Point.new(point.x - @bounds.x, point.y - @bounds.y)

        def token_spans(row, cx)
          return [] unless @owner.highlighter
          tokens = @owner.highlighter.tokens(row.index, row.text)
          raise TypeError, "highlighter tokens must be an Array" unless tokens.is_a?(Array)
          tokens.map do |range, scope|
            finish = range.is_a?(Range) && range.end.is_a?(Integer) ?
              range.end + (range.exclude_end? ? 0 : 1) : nil
            unless range.is_a?(Range) && range.begin.is_a?(Integer) && range.end.is_a?(Integer) &&
                range.begin >= 0 && finish <= row.text.bytesize && finish >= range.begin
              raise TypeError, "highlighter token range must be within its line"
            end
            [range.begin, finish, cx.theme.syntax.color(scope)]
          end
        end

        def paint_caret(bounds, cx)
          offset = @owner.selection.head
          row = @rows.find { |item| item.index == @owner.buffer.line_of(offset) }
          return unless row
          local = (offset - @owner.buffer.line_start(row.index)).clamp(0, row.text.bytesize)
          point = row.paragraph.offset_to_point(local)
          x, y = bounds.x + @gutter + point.x, bounds.y + row.top + point.y
          cx.scene.layer(Scene::LAYER_FOCUS_RING) do
            cx.scene.quad(x, y, 1, @line_height, color: cx.theme.colors.text)
            if @owner.composition && !@owner.composition.empty?
              cx.scene.underline(x, y + @line_height - 2, [@owner.composition.length * @size * 0.6, 1].max,
                color: cx.theme.colors.text)
            end
          end
          cx.window.ime_state = Bounds.new(x, y, 1, @line_height)
        end
      end
    end
  end
end
