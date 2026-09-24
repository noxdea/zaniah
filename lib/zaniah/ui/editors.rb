# frozen_string_literal: true

module Zaniah
  module UI
    class CodeEditor < Component
      class TextBufferAdapter
        attr_reader :source

        def initialize(source)
          @source = source
          reindex
        end

        def line_count = @starts.length
        def line_start(index) = @starts.fetch(index)
        def line_of(offset) = (@starts.bsearch_index { |start| start > offset } || @starts.length) - 1
        def line(index)
          first = line_start(index)
          finish = index + 1 < @starts.length ? @starts[index + 1] - 1 : @text.bytesize
          @text.byteslice(first...finish)
        end

        def replace(range, value) = (@source.replace(range, value); reindex; self)
        def undo = (@source.undo; reindex; self)
        def redo = (@source.redo; reindex; self)
        def can_undo? = @source.can_undo?
        def can_redo? = @source.can_redo?
        def to_s = @text.dup

        private

        def reindex
          @text = @source.to_s
          @starts = [0]
          @text.each_byte.with_index { |byte, index| @starts << index + 1 if byte == 10 }
          @starts.freeze
        end
      end

      BUFFER_METHODS = %i[line_count line line_start line_of replace undo redo].freeze
      attr_reader :buffer, :highlighter, :selection

      def initialize(value = "", buffer: nil, highlighter: nil, language: nil,
        line_numbers: true, read_only: false, wrap: true)
        super()
        raise ArgumentError, "pass either a value or a buffer" if buffer && value != ""
        source = buffer || value
        @buffer = case source
        when TextBuffer then TextBufferAdapter.new(source)
        when String then TextBufferAdapter.new(TextBuffer.new(source.encode(Encoding::UTF_8)))
        else
          raise ArgumentError, "buffer must implement the CodeEditor buffer interface" unless BUFFER_METHODS.all? { |method| source.respond_to?(method) }
          source
        end
        if highlighter && (!highlighter.respond_to?(:tokens) || !highlighter.respond_to?(:edited))
          raise ArgumentError, "highlighter must implement tokens and edited"
        end
        @highlighter = highlighter
        @language, @line_numbers, @read_only = language&.to_sym, !!line_numbers, !!read_only
        @wrap, @selection, @revision = !!wrap, TextSelection.new(0), 0
      end

      def value
        return @buffer.to_s if @buffer.respond_to?(:to_s)
        Array.new(@buffer.line_count) { |index| @buffer.line(index) }.join("\n")
      end

      def line_numbers? = @line_numbers
      def read_only? = @read_only
      def wrap? = @wrap
      def revision = @revision
      def focus_handle = @surface&.focus_handle
      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        @cx = cx
        @surface ||= CodeEditor::Surface.new(self)
      end

      def tui_cells(*)
        count = @buffer.line_count
        count -= 1 if @buffer.line(count - 1).empty?
        Array.new(count) do |index|
          @line_numbers ? format("%4d  %s", index + 1, @buffer.line(index)) : @buffer.line(index)
        end.join("\n")
      end
      def accessibility_node(_cx) = node(:textbox, label: @language ? "#{@language} code editor" : "Code editor", value: value,
        states: {multiline: true, readonly: @read_only}, actions: @read_only ? [] : %i[focus set_value])

      def selection=(selection)
        raise ArgumentError, "selection must be a TextSelection" unless selection.is_a?(TextSelection)
        last = @buffer.line_count - 1
        limit = @buffer.line_start(last) + @buffer.line(last).bytesize
        unless selection.anchor.between?(0, limit) && selection.head.between?(0, limit)
          raise ArgumentError, "selection is outside the buffer"
        end
        @selection = selection
        @cx&.window&.request_frame
        selection
      end

      def replace(range, replacement)
        raise Error, "editor is read-only" if @read_only
        raise ArgumentError, "replacement must be valid UTF-8" unless replacement.is_a?(String) && replacement.encoding == Encoding::UTF_8 && replacement.valid_encoding?
        @buffer.replace(range, replacement)
        @highlighter&.edited(range, replacement)
        @selection = TextSelection.new(range.begin + replacement.bytesize)
        @composition = nil
        @revision += 1
        @surface.ensure_caret_visible if @surface&.heights && @surface.heights.count == @buffer.line_count
        @on_change&.call(value, @cx)
        @cx&.window&.request_frame
        self
      end

      def replace_selection(value) = replace(@selection.range, value)

      def validate_text_action(action)
        return !@read_only && (!@buffer.respond_to?(:can_undo?) || @buffer.can_undo?) if action == :undo
        return !@read_only && (!@buffer.respond_to?(:can_redo?) || @buffer.can_redo?) if action == :redo
        return !@selection.collapsed? if action == :copy
        return !@read_only if %i[cut paste delete_backward delete_forward insert_newline insert_tab].include?(action)
        return true if %i[copy select_all move_left move_right select_left select_right line_up line_down
          line_start line_end select_line_start select_line_end document_start document_end word_left word_right
          select_word_left select_word_right].include?(action)
        nil
      end

      def text_action(action)
        head = @selection.head
        case action
        when :select_all then self.selection = TextSelection.new(0, value.bytesize)
        when :copy then @cx.window.clipboard = value.byteslice(@selection.range)
        when :cut
          @cx.window.clipboard = value.byteslice(@selection.range)
          replace_selection("")
        when :paste then replace_selection(@cx.window.clipboard.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace))
        when :undo, :redo
          @buffer.public_send(action)
          @revision += 1
          current = value
          @selection = TextSelection.new([head, current.bytesize].min)
          @highlighter&.edited(0...current.bytesize, current)
          @on_change&.call(current, @cx)
          @cx&.window&.request_frame
        when :move_left, :move_right, :select_left, :select_right,
          :word_left, :word_right, :select_word_left, :select_word_right
          target = if action.to_s.include?("word")
            Unicode.word_boundary(value, head, action.to_s.end_with?("left") ? :left : :right)
          elsif action.to_s.end_with?("left")
            Unicode.previous_boundary(value, head)
          else
            Unicode.next_boundary(value, head)
          end
          self.selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
        when :line_start, :line_end, :select_line_start, :select_line_end, :line_up, :line_down
          line = @buffer.line_of(head)
          target = case action
          when :line_start, :select_line_start then @buffer.line_start(line)
          when :line_end, :select_line_end then @buffer.line_start(line) + @buffer.line(line).bytesize
          else
            destination = (line + (action == :line_up ? -1 : 1)).clamp(0, @buffer.line_count - 1)
            column = head - @buffer.line_start(line)
            @buffer.line_start(destination) + [column, @buffer.line(destination).bytesize].min
          end
          self.selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
        when :document_start then self.selection = TextSelection.new(0)
        when :document_end then self.selection = TextSelection.new(value.bytesize)
        when :delete_backward
          first = @selection.collapsed? ? Unicode.previous_boundary(value, head) : @selection.range.begin
          replace(first...@selection.range.end, "")
        when :delete_forward
          finish = @selection.collapsed? ? Unicode.next_boundary(value, head) : @selection.range.end
          replace(@selection.range.begin...finish, "")
        when :insert_newline then replace_selection("\n")
        when :insert_tab then replace_selection("  ")
        else return false
        end
        true
      end

      def input(event)
        case event
        when Input::TextInput
          return false if @read_only
          replace_selection(event.text)
        when Input::Composition
          return false if @read_only
          @composition = event.text
        else return false
        end
        @cx&.window&.request_frame
        true
      end

      def composition = @composition
    end

    class RichText < Component
      Span = Data.define(:start, :finish, :style)
      Embed = Data.define(:key, :offset, :width, :height, :factory)
      STYLE_KEYS = %i[bold italic size color font link underline underline_color strikethrough background baseline letter_spacing ruby combine_upright].freeze
      LIST_STYLES = %i[none bullet ordered].freeze
      BASELINES = %i[normal superscript subscript].freeze
      UNDERLINES = %i[single double wavy].freeze

      attr_reader :buffer, :selection, :paragraph_styles, :embeds, :writing_mode, :text_orientation

      def initialize(runs, selectable: true, editable: false, writing_mode: :horizontal_tb, text_orientation: :mixed)
        super()
        raise ArgumentError, "writing mode must be horizontal_tb or vertical_rl" unless %i[horizontal_tb vertical_rl].include?(writing_mode)
        raise ArgumentError, "text orientation must be mixed or upright" unless %i[mixed upright].include?(text_orientation)
        @writing_mode, @text_orientation = writing_mode, text_orientation
        text, @spans = normalize_runs(runs)
        @buffer = TextBuffer.new(text)
        @paragraph_styles = Array.new(text.count("\n") + 1) { {} }
        @embeds = []
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
        raise ArgumentError, "atomic span cannot cross a newline" if (changes[:ruby] || changes[:combine_upright]) && text.byteslice(first...finish).include?("\n")
        if @spans.any? { |span| (span.style[:ruby] || span.style[:combine_upright]) && span.start < finish && span.finish > first && (first > span.start || finish < span.finish) }
          raise ArgumentError, "atomic span must be styled as one cluster"
        end
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
        @embeds = @embeds.map { |embed| embed.offset >= offset ? embed.with(offset: embed.offset + size) : embed }
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
        @embeds = @embeds.filter_map do |embed|
          next if embed.offset >= first && embed.offset < finish
          embed.offset >= finish ? embed.with(offset: embed.offset - (finish - first)) : embed
        end
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
        @embeds = @embeds.filter_map do |embed|
          next if embed.offset >= first && embed.offset < finish
          embed.offset >= finish ? embed.with(offset: embed.offset - (finish - first) + value.bytesize) : embed
        end
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

      def paragraph_style(range, align: nil, list: nil, level: nil, indent: nil, quote: nil,
        background: nil, spacing_before: nil, spacing_after: nil)
        first, finish = checked_range(range)
        raise ArgumentError, "align must be start, center, end, or justify" if align && !%i[start center end justify].include?(align)
        raise ArgumentError, "list must be none, bullet, or ordered" if list && !LIST_STYLES.include?(list)
        raise ArgumentError, "level must be a nonnegative integer" if level && (!level.is_a?(Integer) || level.negative?)
        raise ArgumentError, "indent must be nonnegative" if indent && (!indent.is_a?(Numeric) || !indent.finite? || indent.negative?)
        raise ArgumentError, "quote must be boolean or a color" if quote && quote != true && !quote.is_a?(String) && !quote.is_a?(Color)
        [spacing_before, spacing_after].compact.each do |spacing|
          raise ArgumentError, "paragraph spacing must be nonnegative" unless spacing.is_a?(Numeric) && spacing.finite? && !spacing.negative?
        end
        first_line, last_line = @buffer.line_at(first), @buffer.line_at(finish)
        last_line = [last_line, @paragraph_styles.length - 1].min
        values = {align: align, list: list, level: level, indent: indent, quote: quote,
          background: background, spacing_before: spacing_before, spacing_after: spacing_after}.compact
        return self if values.empty?
        record_edit
        @append_start = nil
        (first_line..last_line).each { |index| @paragraph_styles[index] = @paragraph_styles[index].merge(values).freeze }
        @on_change&.call(text, self)
        @cx&.window&.request_frame
        self
      end

      def append(value, style: nil)
        start = text.rindex("\n")&.+(1) || 0
        insert(@buffer.bytesize, value, style: style)
        @append_start = start
        self
      end

      def insert_embed(offset, key:, width:, height:, &factory)
        raise ArgumentError, "embed requires a block" unless factory
        raise ArgumentError, "embed key is already present" if @embeds.any? { |embed| embed.key == key }
        [width, height].each do |dimension|
          raise ArgumentError, "embed dimensions must be finite and nonnegative" unless dimension.is_a?(Numeric) && dimension.finite? && !dimension.negative?
        end
        offset = checked_offset(offset)
        insert(offset, "\uFFFC")
        @embeds << Embed.new(key, offset, width.to_f, height.to_f, factory)
        self
      end

      def build(cx) = (@cx = cx; RichTextSurface.new(self))
      def tui_cells(*) = ruby_reading
      def accessibility_node(_cx) = node(@editable ? :textbox : :text, label: "Rich text", value: ruby_reading,
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
        when :move_left then self.selection = TextSelection.new(@selection.collapsed? ? previous_text_boundary(head) : @selection.range.begin)
        when :move_right then self.selection = TextSelection.new(@selection.collapsed? ? next_text_boundary(head) : @selection.range.end)
        when :select_left then self.selection = TextSelection.new(@selection.anchor, previous_text_boundary(head))
        when :select_right then self.selection = TextSelection.new(@selection.anchor, next_text_boundary(head))
        when :word_left, :word_right, :select_word_left, :select_word_right
          direction = action.to_s.end_with?("left") ? :left : :right
          target = snap_atomic(Unicode.word_boundary(text, head, direction), direction)
          self.selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
        when :line_up, :line_down
          direction = action == :line_up ? :left : :right
          self.selection = TextSelection.new(snap_atomic(Unicode.neighbor_line_offset(text, head, direction == :left ? -1 : 1), direction))
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
        @append_start = nil
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

      def ruby_reading
        result, offset = +"", 0
        @spans.each do |span|
          next unless span.style[:ruby]
          result << text.byteslice(offset...span.finish)
          result << "（#{span.style[:ruby]}）"
          offset = span.finish
        end
        result << text.byteslice(offset..)
      end

      private

      def edit_state = [text, @spans, @paragraph_styles.dup, @selection, @embeds.dup]

      def record_edit
        @undo_states << edit_state
        @redo_states.clear
      end

      def restore_edit(action)
        from, to = action == :undo ? [@undo_states, @redo_states] : [@redo_states, @undo_states]
        return false if from.empty?
        to << edit_state
        value, @spans, @paragraph_styles, @selection, @embeds = from.pop
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
          raise ArgumentError, "atomic span cannot cross a newline" if (style[:ruby] || style[:combine_upright]) && part.include?("\n")
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
        raise ArgumentError, "invalid underline style" if style[:underline] && !UNDERLINES.include?(style[:underline])
        raise ArgumentError, "invalid baseline" if style[:baseline] && !BASELINES.include?(style[:baseline])
        if style[:letter_spacing] && (!style[:letter_spacing].is_a?(Numeric) || !style[:letter_spacing].finite?)
          raise ArgumentError, "letter spacing must be finite"
        end
        if style[:ruby] && (!style[:ruby].is_a?(String) || style[:ruby].encoding != Encoding::UTF_8 || style[:ruby].empty? || !style[:ruby].valid_encoding? || style[:ruby].include?("\n"))
          raise ArgumentError, "ruby must be a nonempty UTF-8 annotation without newlines"
        end
        if style.key?(:combine_upright) && ![true, false].include?(style[:combine_upright])
          raise ArgumentError, "combine_upright must be boolean"
        end
        raise ArgumentError, "ruby and combine_upright cannot be combined" if style[:ruby] && style[:combine_upright]
        style
      end

      def merge_spans(spans)
        spans.sort_by(&:start).each_with_object([]) do |span, result|
          next if span.start == span.finish
          previous = result.last
          if previous && previous.finish == span.start && previous.style == span.style && !span.style[:ruby] && !span.style[:combine_upright]
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
        raise ArgumentError, "offset splits an atomic text cluster" if @spans.any? { |span| (span.style[:ruby] || span.style[:combine_upright]) && offset > span.start && offset < span.finish }
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
        range = @selection.collapsed? ? previous_text_boundary(@selection.head)...@selection.head : @selection.range
        delete(range)
      end

      def delete_forward
        range = @selection.collapsed? ? @selection.head...next_text_boundary(@selection.head) : @selection.range
        delete(range)
      end

      def previous_text_boundary(offset)
        previous = Unicode.previous_boundary(text, offset)
        span = @spans.find { |item| (item.style[:ruby] || item.style[:combine_upright]) && previous > item.start && previous < item.finish }
        span ? span.start : previous
      end

      def next_text_boundary(offset)
        following = Unicode.next_boundary(text, offset)
        span = @spans.find { |item| (item.style[:ruby] || item.style[:combine_upright]) && following > item.start && following < item.finish }
        span ? span.finish : following
      end

      def snap_atomic(offset, direction)
        span = @spans.find { |item| (item.style[:ruby] || item.style[:combine_upright]) && offset > item.start && offset < item.finish }
        return offset unless span
        direction == :left ? span.start : span.finish
      end

      def move_line_edge(action, edge)
        line = @buffer.line_at(@selection.head)
        start = @buffer.offset_at(line, 0)
        finish = text.index("\n", start) || text.bytesize
        target = snap_atomic(edge == :start ? start : finish, edge == :start ? :left : :right)
        self.selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
      end
    end
  end
end
