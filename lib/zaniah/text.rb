# frozen_string_literal: true

module Zaniah
  class Text < Element
    attr_reader :text, :font_size, :selection, :buffer

    def initialize(text, size: 14, color: "#ddd", font: nil, wrap: :none,
      line_height: nil, letter_spacing: 0, align: :start, ellipsis: false, kinsoku: :push)
      super()
      @text, @font_size, @color, @font = text, size, color, font
      @wrap, @line_height, @letter_spacing = wrap, line_height, letter_spacing
      @text_align, @ellipsis, @kinsoku = align, ellipsis, kinsoku
    end

    def measured(&block) = (@measure = block; self)
    def text_color = @color
    def selection=(value)
      raise ArgumentError, "expected a TextSelection" unless value.is_a?(TextSelection)
      raise ArgumentError, "selection is outside the text" unless value.anchor <= @text.bytesize && value.head <= @text.bytesize
      raise ArgumentError, "selection splits a grapheme cluster" unless [value.anchor, value.head].all? { |offset| Unicode.grapheme_boundary?(@text, offset) }
      @selection = value
    end

    def wrap(mode = :word, line_height: @line_height, letter_spacing: @letter_spacing,
      align: @text_align, ellipsis: @ellipsis, kinsoku: @kinsoku)
      @wrap, @line_height, @letter_spacing = mode, line_height, letter_spacing
      @text_align, @ellipsis, @kinsoku = align, ellipsis, kinsoku
      self
    end

    def selectable(value = true)
      @selectable = value
      @selection ||= TextSelection.new(0)
      return self unless value
      focusable(context: {in_text_field: true}) { |action| text_action(action) }
      @focus_handle.on_input = ->(event) { text_input(event) }
      on_mouse_down { |event, _| begin_selection(event) }
      on_drag { |event, _| extend_selection(event) }
      self
    end

    def editable(buffer = nil)
      @editable = true
      @buffer = buffer || TextBuffer.new(@text)
      raise ArgumentError, "editable text requires a TextBuffer" unless @buffer.is_a?(TextBuffer)
      @text = @buffer.to_s
      selectable
    end

    def request_layout(cx)
      @text = @buffer.to_s if @buffer
      value = display_text
      @paragraph = nil
      @line = cx.text_system ? cx.text_system.layout_line(value, font: @font, size: @font_size) : approximate_line(value)
      line_height = @line ? @line.ascent + @line.descent : 0
      unless @wrap == :none && !@ellipsis
        available = @style[:width]
        available = available.resolve(cx.window.content_size.width) if available.is_a?(Length)
        available = cx.window.content_size.width unless available.is_a?(Numeric)
        @paragraph = paragraph(value, available, cx.text_system)
      end
      measurement = @measure || if @wrap == :none && !@ellipsis
        ->(_width, _height) { [@line ? @line.width : value.length * @font_size * 0.6, [@font_size * 1.4, line_height].max, @font_size] }
      else
        lambda do |width, _height|
          limit = width.finite? ? [width, 0].max : Float::INFINITY
          @paragraph = paragraph(value, limit, cx.text_system)
          [@paragraph.width, @paragraph.height, @paragraph.lines.first&.layout&.ascent || @font_size]
        end
      end
      @layout_node = Layout::Node.new(style: @style, measure: measurement)
    end

    def prepaint(bounds, state, cx)
      @text_bounds = bounds
      super
    end

    def paint(bounds, state, prepaint, cx)
      super
      color = @resolved_style[:text_color] || @color
      paint_selection(bounds, cx) if @selectable && @selection && !@selection.collapsed?
      cx.scene.layer(Scene::LAYER_SELECTION) do
        if @paragraph
          if cx.text_system.respond_to?(:paint_paragraph)
            cx.text_system.paint_paragraph(cx.scene, @paragraph, x: bounds.x, y: bounds.y, color: color)
          elsif cx.text_system
            @paragraph.lines.each { |item| cx.text_system.paint_line(cx.scene, item.layout, x: bounds.x + item.x, y: bounds.y + item.y + item.layout.ascent, color: color) }
          end
        elsif @line && cx.text_system
          cx.text_system.paint_line(cx.scene, @line, x: bounds.x, y: bounds.y + @line.ascent, color: color)
        end
      end
      paint_composition(bounds, cx) if @buffer&.composition
      paint_caret(bounds, cx) if @editable && @selection&.collapsed? && cx.dispatcher.focused == @focus_handle
      if cx.window.respond_to?(:text_runs)
        if @paragraph
          @paragraph.lines.each { |item| cx.window.text_runs << [bounds.x + item.x, bounds.y + item.y, item.layout.text, color] }
        else
          cx.window.text_runs << [bounds.x, bounds.y, @line.text, color]
        end
      end
    end

    private

    def display_text = @buffer&.composition ? @buffer.preview(@selection.head) : @text

    def begin_selection(event)
      offset = offset_at(event.position)
      @selection = if event.click_count >= 3 && @paragraph
        range = @paragraph.line_range_at(offset)
        TextSelection.new(range.begin, range.end)
      elsif event.click_count == 2
        range = Unicode.word_range_at(@text, [offset, @text.bytesize].min)
        TextSelection.new(range.begin, range.end)
      else
        TextSelection.new([offset, @text.bytesize].min)
      end
    end

    def extend_selection(event)
      @selection = TextSelection.new(@selection.anchor, [offset_at(event.position), @text.bytesize].min)
    end

    def offset_at(position)
      point = Point.new(position.x - @text_bounds.x, position.y - @text_bounds.y)
      @paragraph ? @paragraph.hit_test(point) : @line ? @line.index_for_x(point.x) : 0
    end

    def text_action(action)
      return false unless @selection
      head = @selection.head
      case action
      when :select_all then @selection = TextSelection.new(0, @text.bytesize)
      when :move_left then @selection = TextSelection.new(@selection.collapsed? ? Unicode.previous_boundary(@text, head) : @selection.range.begin)
      when :move_right then @selection = TextSelection.new(@selection.collapsed? ? Unicode.next_boundary(@text, head) : @selection.range.end)
      when :select_left then @selection = TextSelection.new(@selection.anchor, Unicode.previous_boundary(@text, head))
      when :select_right then @selection = TextSelection.new(@selection.anchor, Unicode.next_boundary(@text, head))
      when :line_start, :select_line_start then move_to_line_edge(action, :start)
      when :line_end, :select_line_end then move_to_line_edge(action, :end)
      when :delete_backward then delete_backward
      when :delete_forward then delete_forward
      when :insert_newline then replace_selection("\n") if @editable
      else return false
      end
      true
    end

    def text_input(event)
      case event
      when Input::TextInput
        return false unless @editable
        replace_selection(event.text)
      when Input::Composition
        return false unless @editable
        @buffer.set_composition(event.text, selection: event.selection)
      else return false
      end
      true
    end

    def replace_selection(value)
      range = @selection.range
      range.begin == range.end ? @buffer.insert(range.begin, value) : @buffer.replace(range, value)
      at = range.begin + value.bytesize
      @selection = TextSelection.new(at)
      @text = @buffer.to_s
    end

    def delete_backward
      return false unless @editable
      range = @selection.collapsed? ? Unicode.previous_boundary(@text, @selection.head)...@selection.head : @selection.range
      delete_range(range)
    end

    def delete_forward
      return false unless @editable
      range = @selection.collapsed? ? @selection.head...Unicode.next_boundary(@text, @selection.head) : @selection.range
      delete_range(range)
    end

    def delete_range(range)
      return if range.begin == range.end
      @buffer.delete(range)
      @selection = TextSelection.new(range.begin)
      @text = @buffer.to_s
    end

    def move_to_line_edge(action, edge)
      line = @text.byteslice(0...@selection.head).count("\n")
      target = if edge == :start
        @text.split("\n", -1).take(line).sum { |value| value.bytesize + 1 }
      else
        start = @text.split("\n", -1).take(line).sum { |value| value.bytesize + 1 }
        start + (@text.split("\n", -1)[line]&.bytesize || 0)
      end
      @selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
    end

    def paint_selection(bounds, cx)
      range = @selection.range
      selection_lines.each do |line, start, finish, x, y, height|
        first, last = [range.begin, start].max, [range.end, finish].min
        next if last <= first
        left = line.x_for_index(first - start)
        right = line.x_for_index(last - start)
        cx.scene.layer(Scene::LAYER_SELECTION) do
          cx.scene.quad(bounds.x + x + left, bounds.y + y, [right - left, 1].max, height,
            color: cx.theme.colors.selection)
        end
      end
    end

    def paint_caret(bounds, cx)
      offset = @selection.head + (@buffer.composition&.selection&.first || 0)
      point = point_at(offset)
      height = @paragraph ? @paragraph.lines.first.height : [@font_size * 1.4, @line ? @line.ascent + @line.descent : 0].max
      cx.scene.layer(Scene::LAYER_FOCUS_RING) { cx.scene.quad(bounds.x + point.x, bounds.y + point.y, 1, height, color: @resolved_style[:text_color] || @color) }
      cx.window.ime_state = Bounds.new(bounds.x + point.x, bounds.y + point.y, 1, height)
    end

    def paint_composition(bounds, cx)
      start = @selection.head
      first, last = point_at(start), point_at(start + @buffer.composition.text.bytesize)
      cx.scene.layer(Scene::LAYER_FOCUS_RING) do
        cx.scene.underline(bounds.x + first.x, bounds.y + first.y + @font_size * 1.25,
          [last.x - first.x, 1].max, color: @resolved_style[:text_color] || @color)
      end
    end

    def point_at(offset)
      return @paragraph.offset_to_point(offset) if @paragraph
      Point.new(@line ? @line.x_for_index(offset) : 0, 0)
    end

    def selection_lines
      return @paragraph.lines.map { |item| [item.layout, item.start, item.finish, item.x, item.y, item.height] } if @paragraph
      [[@line, 0, @text.bytesize, 0, 0, [@font_size * 1.4, @line ? @line.ascent + @line.descent : 0].max]]
    end

    def approximate_line(value)
      byte, x, carets = 0, 0.0, [[0, 0.0]]
      value.grapheme_clusters.each do |cluster|
        byte += cluster.bytesize
        x += Unicode.width(cluster) * @font_size * 0.6
        carets << [byte, x]
      end
      TextSystem::LineLayout.new(value.dup.freeze, [].freeze, x, @font_size, @font_size * 0.4, @font_size, carets.freeze)
    end

    def paragraph(value, width, typesetter)
      TextSystem::Paragraph.new(value, width: width, size: @font_size, font: @font,
        wrap: @wrap, line_height: @line_height, letter_spacing: @letter_spacing,
        align: @text_align, ellipsis: @ellipsis, kinsoku: @kinsoku, typesetter: typesetter)
    end
  end
end
