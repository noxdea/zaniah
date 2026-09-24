# frozen_string_literal: true

module Zaniah
  module UI
    class CodeEditor < Component
      attr_reader :buffer

      def initialize(value = "", language: nil, line_numbers: true, read_only: false)
        super()
        @buffer = value.is_a?(TextBuffer) ? value : TextBuffer.new(value.to_s)
        @language, @line_numbers, @read_only = language&.to_sym, !!line_numbers, !!read_only
      end

      def value = @buffer.to_s
      def focus_handle = @editor&.focus_handle
      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        @editor = Text.new(value, size: cx.theme.typography.size_sm, color: cx.theme.colors.text).wrap(:word)
        @editor.editable(@buffer).on_change { |text| @on_change&.call(text, @cx) } unless @read_only
        @cx = cx
        content = Div.new.flex_row.gap(cx.theme.spacing[2])
        if @line_numbers
          numbers = (1..[value.count("\n") + 1, 1].max).to_a.join("\n").encode(Encoding::UTF_8)
          content.child(Text.new(numbers, size: cx.theme.typography.size_sm, color: cx.theme.colors.text_muted).wrap(:word))
        end
        content.child(Div.new.flex_1.child(@editor))
        ScrollView.new(scrollbar: :overlay).child(content)
      end

      def tui_cells(*) = value.lines.map.with_index(1) { |line, number| @line_numbers ? format("%4d  %s", number, line.chomp) : line.chomp }.join("\n")
      def accessibility_node(_cx) = node(:textbox, label: @language ? "#{@language} code editor" : "Code editor", value: value,
        states: {multiline: true, readonly: @read_only}, actions: @read_only ? [] : %i[focus set_value])
    end

    class RichText < Component
      Span = Data.define(:start, :finish, :style)
      STYLE_KEYS = %i[bold italic size color font link].freeze
      LIST_STYLES = %i[none bullet ordered].freeze

      attr_reader :buffer, :selection, :paragraph_styles

      def initialize(runs, selectable: true, editable: false)
        super()
        text, @spans = normalize_runs(runs)
        @buffer = TextBuffer.new(text)
        @paragraph_styles = Array.new(text.count("\n") + 1) { {} }
        @selection, @selectable, @editable = TextSelection.new(0), !!selectable, !!editable
        @undo_states, @redo_states = [], []
      end

      def text = @buffer.to_s

      def runs
        slices = []
        offset = 0
        @spans.each do |span|
          if offset < span.start
            slices << {text: text.byteslice(offset...span.start)}
          end
          slices << {text: text.byteslice(span.start...span.finish), **span.style}
          offset = span.finish
        end
        slices << {text: text.byteslice(offset..)} if offset < text.bytesize
        slices.freeze
      end

      def spans = @spans
      def editable? = @editable
      def on_change(&block) = (@on_change = block; self)
      def on_select(&block) = (@on_select = block; self)

      def selection=(value)
        raise ArgumentError, "expected a TextSelection" unless value.is_a?(TextSelection)
        checked_offset(value.anchor)
        checked_offset(value.head)
        @selection = value
        @on_select&.call(value, self)
        @cx&.window&.request_frame
        value
      end

      def apply(range, style)
        first, finish = checked_range(range)
        changes = normalize_style(style)
        return self if first == finish || changes.empty?
        record_edit
        boundaries = [0, text.bytesize, first, finish, *@spans.flat_map { |span| [span.start, span.finish] }].uniq.sort
        @spans = merge_spans(boundaries.each_cons(2).filter_map do |from, to|
          next if from == to
          current = style_for_range(from)
          updated = current.dup
          changes.each { |key, value| value.nil? ? updated.delete(key) : updated[key] = value } if from >= first && to <= finish
          Span.new(from, to, updated.freeze) unless updated.empty?
        end)
        changed
      end

      def insert(offset, value, style: nil)
        offset = checked_offset(offset)
        validate_text(value)
        return self if value.empty?
        record_edit
        inherited = style ? normalize_style(style) : style_at(offset)
        size, newlines = value.bytesize, value.count("\n")
        @buffer.insert(offset, value)
        @spans = merge_spans(@spans.flat_map do |span|
          if span.finish <= offset
            [span]
          elsif span.start >= offset
            [Span.new(span.start + size, span.finish + size, span.style)]
          else
            [Span.new(span.start, offset, span.style), Span.new(offset + size, span.finish + size, span.style)]
          end
        end + (inherited.empty? ? [] : [Span.new(offset, offset + size, inherited.freeze)]))
        if newlines.positive?
          line = @buffer.line_at(offset)
          @paragraph_styles.insert(line + 1, *Array.new(newlines) { @paragraph_styles[line].dup.freeze })
        end
        sync_paragraph_styles
        @selection = TextSelection.new(offset + size)
        changed
      end

      def delete(range)
        first, finish = checked_range(range)
        return self if first == finish
        record_edit
        old = text
        first_line = @buffer.line_at(first)
        removed_lines = old.byteslice(first...finish).count("\n")
        @buffer.delete(first...finish)
        delta = finish - first
        @spans = merge_spans(@spans.filter_map do |span|
          from = map_offset(span.start, first, finish, delta)
          to = map_offset(span.finish, first, finish, delta)
          Span.new(from, to, span.style) if to > from
        end)
        @paragraph_styles.slice!(first_line + 1, removed_lines) if removed_lines.positive?
        sync_paragraph_styles
        @selection = TextSelection.new(first)
        changed
      end

      def replace(range, value, style: nil)
        first, finish = checked_range(range)
        validate_text(value)
        return delete(first...finish) if value.empty?
        record_edit
        inherited = style ? normalize_style(style) : style_at(first)
        first_line, last_line = @buffer.line_at(first), @buffer.line_at(finish)
        before_styles = @paragraph_styles.take(first_line)
        paragraph_style = @paragraph_styles.fetch(first_line, {}).dup.freeze
        after_styles = @paragraph_styles.drop(last_line + 1)
        @buffer.replace(first...finish, value)
        delta = finish - first
        size = value.bytesize
        replacement_spans = @spans.flat_map do |span|
          if finish == first
            if span.finish <= first
              [span]
            elsif span.start >= first
              [Span.new(span.start + size, span.finish + size, span.style)]
            else
              [Span.new(span.start, first, span.style), Span.new(first + size, span.finish + size, span.style)]
            end
          elsif span.finish <= first
            [span]
          elsif span.start >= finish
            [Span.new(span.start - delta + size, span.finish - delta + size, span.style)]
          else
            pieces = []
            pieces << Span.new(span.start, first, span.style) if span.start < first
            pieces << Span.new(first + size, span.finish - delta + size, span.style) if span.finish > finish
            pieces
          end
        end
        replacement_spans << Span.new(first, first + size, inherited.freeze) unless inherited.empty?
        @spans = merge_spans(replacement_spans)
        replacement_paragraphs = Array.new(value.count("\n") + 1) { paragraph_style }
        @paragraph_styles = before_styles + replacement_paragraphs + after_styles
        sync_paragraph_styles
        @selection = TextSelection.new(first + size)
        changed
      end

      def paragraph_style(range, align: nil, list: nil, level: nil)
        first, finish = checked_range(range)
        raise ArgumentError, "align must be start, center, end, or justify" if align && !%i[start center end justify].include?(align)
        raise ArgumentError, "list must be none, bullet, or ordered" if list && !LIST_STYLES.include?(list)
        raise ArgumentError, "level must be a nonnegative integer" if level && (!level.is_a?(Integer) || level.negative?)
        first_line, last_line = @buffer.line_at(first), @buffer.line_at(finish)
        last_line = [last_line, @paragraph_styles.length - 1].min
        values = {align: align, list: list, level: level}.compact
        return self if values.empty?
        record_edit
        (first_line..last_line).each { |index| @paragraph_styles[index] = @paragraph_styles[index].merge(values).freeze }
        @on_change&.call(text, self)
        @cx&.window&.request_frame
        self
      end

      def build(cx) = (@cx = cx; RichTextSurface.new(self))
      def tui_cells(*) = text
      def accessibility_node(_cx) = node(@editable ? :textbox : :text, label: "Rich text", value: text,
        states: {multiline: true, readonly: !@editable}, actions: @editable ? %i[focus set_value] : [])

      def display_text
        return text unless @buffer.composition
        range = @selection.range
        text.byteslice(0...range.begin) + @buffer.composition.text + text.byteslice(range.end..)
      end

      def text_action(action)
        head = @selection.head
        case action
        when :select_all then self.selection = TextSelection.new(0, text.bytesize)
        when :copy then @cx.window.clipboard = text.byteslice(@selection.range)
        when :cut
          @cx.window.clipboard = text.byteslice(@selection.range)
          delete(@selection.range)
        when :paste then replace_selection(@cx.window.clipboard.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace))
        when :undo, :redo then restore_edit(action)
        when :move_left then self.selection = TextSelection.new(@selection.collapsed? ? Unicode.previous_boundary(text, head) : @selection.range.begin)
        when :move_right then self.selection = TextSelection.new(@selection.collapsed? ? Unicode.next_boundary(text, head) : @selection.range.end)
        when :select_left then self.selection = TextSelection.new(@selection.anchor, Unicode.previous_boundary(text, head))
        when :select_right then self.selection = TextSelection.new(@selection.anchor, Unicode.next_boundary(text, head))
        when :word_left, :word_right, :select_word_left, :select_word_right
          direction = action.to_s.end_with?("left") ? :left : :right
          target = Unicode.word_boundary(text, head, direction)
          self.selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
        when :line_up, :line_down
          self.selection = TextSelection.new(Unicode.neighbor_line_offset(text, head, action == :line_up ? -1 : 1))
        when :document_start then self.selection = TextSelection.new(0)
        when :document_end then self.selection = TextSelection.new(text.bytesize)
        when :line_start, :select_line_start then move_line_edge(action, :start)
        when :line_end, :select_line_end then move_line_edge(action, :end)
        when :delete_backward then delete_backward
        when :delete_forward then delete_forward
        when :insert_newline then replace_selection("\n") if @editable
        else return false
        end
        true
      end

      def validate_text_action(action)
        case action
        when :copy then !@selection.collapsed?
        when :cut then @editable && !@selection.collapsed?
        when :paste then @editable && !@buffer.composition
        when :undo then @editable && !@buffer.composition && !@undo_states.empty?
        when :redo then @editable && !@redo_states.empty?
        when :delete_backward, :delete_forward, :insert_newline then @editable
        when :select_all, :move_left, :move_right, :select_left, :select_right,
          :word_left, :word_right, :select_word_left, :select_word_right,
          :line_up, :line_down, :document_start, :document_end,
          :line_start, :line_end, :select_line_start, :select_line_end then true
        end
      end

      def input(event)
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

      def changed
        @on_change&.call(text, self)
        @cx&.window&.request_frame
        self
      end

      def style_at(offset)
        span = @spans.find { |item| offset >= item.start && offset < item.finish } ||
          @spans.reverse.find { |item| item.finish == offset }
        span ? span.style.dup : {}
      end

      def style_for_range(offset)
        @spans.find { |span| offset >= span.start && offset < span.finish }&.style&.dup || {}
      end

      def paragraph_style_at(offset)
        @paragraph_styles.fetch(@buffer.line_at([offset, text.bytesize].min), {})
      end

      private

      def edit_state = [text, @spans, @paragraph_styles.dup, @selection]

      def record_edit
        @undo_states << edit_state
        @redo_states.clear
      end

      def restore_edit(action)
        from, to = action == :undo ? [@undo_states, @redo_states] : [@redo_states, @undo_states]
        return false if from.empty?
        to << edit_state
        value, @spans, @paragraph_styles, @selection = from.pop
        @buffer.replace(0...@buffer.bytesize, value)
        changed
      end

      def normalize_runs(value)
        text, spans = +"", []
        Array(value).each do |run|
          run = {text: run} unless run.is_a?(Hash)
          raise ArgumentError, "rich text runs require text" unless run.key?(:text)
          part = run[:text].to_s.encode(Encoding::UTF_8)
          style = normalize_style(run.reject { |key, _| key.to_sym == :text })
          first = text.bytesize
          text << part
          spans << Span.new(first, text.bytesize, style.freeze) unless part.empty? || style.empty?
        end
        [text, merge_spans(spans)]
      end

      def normalize_style(value)
        raise ArgumentError, "rich text style must be a Hash" unless value.is_a?(Hash)
        style = value.to_h { |key, item| [key.to_sym, item] }
        unknown = style.keys - STYLE_KEYS
        raise ArgumentError, "unsupported rich text style: #{unknown.join(', ')}" unless unknown.empty?
        if style[:size] && (!style[:size].is_a?(Numeric) || !style[:size].finite? || !style[:size].positive?)
          raise ArgumentError, "font size must be finite and positive"
        end
        style
      end

      def merge_spans(spans)
        spans.sort_by(&:start).each_with_object([]) do |span, result|
          next if span.start == span.finish
          previous = result.last
          if previous && previous.finish == span.start && previous.style == span.style
            result[-1] = Span.new(previous.start, span.finish, span.style)
          else
            result << span
          end
        end.freeze
      end

      def checked_range(range)
        raise ArgumentError, "expected a Range" unless range.is_a?(Range)
        first, finish = Integer(range.begin), Integer(range.end)
        finish += 1 unless range.exclude_end?
        checked_offset(first)
        checked_offset(finish)
        raise ArgumentError, "range is reversed" if finish < first
        [first, finish]
      end

      def checked_offset(offset)
        raise ArgumentError, "offset is outside text" unless offset.is_a?(Integer) && offset.between?(0, text.bytesize)
        raise ArgumentError, "offset splits a grapheme cluster" unless Unicode.grapheme_boundary?(text, offset)
        offset
      end

      def validate_text(value)
        raise ArgumentError, "text must be valid UTF-8" unless value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding?
      end

      def map_offset(offset, first, finish, delta)
        return offset if offset <= first
        return offset - delta if offset >= finish
        first
      end

      def sync_paragraph_styles
        length = text.count("\n") + 1
        @paragraph_styles = @paragraph_styles.take(length)
        @paragraph_styles << {}.freeze while @paragraph_styles.length < length
      end

      def replace_selection(value)
        range = @selection.range
        if range.begin == range.end
          insert(range.begin, value)
        else
          replace(range, value)
        end
      end

      def delete_backward
        range = @selection.collapsed? ? Unicode.previous_boundary(text, @selection.head)...@selection.head : @selection.range
        delete(range)
      end

      def delete_forward
        range = @selection.collapsed? ? @selection.head...Unicode.next_boundary(text, @selection.head) : @selection.range
        delete(range)
      end

      def move_line_edge(action, edge)
        line = @buffer.line_at(@selection.head)
        start = @buffer.offset_at(line, 0)
        finish = text.index("\n", start) || text.bytesize
        target = edge == :start ? start : finish
        self.selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
      end
    end
  end
end
