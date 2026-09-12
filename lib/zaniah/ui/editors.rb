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
      attr_reader :runs

      def initialize(runs, selectable: true)
        super()
        @runs, @selectable = normalize_runs(runs), !!selectable
      end

      def build(cx)
        Div.new.flex_row.style(flex_wrap: :wrap).children(@runs.map do |run|
          text = Text.new(run[:text], size: run[:size] || cx.theme.typography.size_md,
            color: run[:color] || cx.theme.colors.text)
          text.selectable if @selectable
          text
        end)
      end

      def tui_cells(*) = @runs.map { |run| run[:text] }.join
      def accessibility_node(_cx) = node(:text, label: tui_cells)

      private

      def normalize_runs(value)
        Array(value).map do |run|
          run = {text: run} unless run.is_a?(Hash)
          raise ArgumentError, "rich text runs require text" unless run.key?(:text)
          {text: run[:text].to_s.encode(Encoding::UTF_8), color: run[:color], size: run[:size]}.freeze
        end.freeze
      end
    end
  end
end
