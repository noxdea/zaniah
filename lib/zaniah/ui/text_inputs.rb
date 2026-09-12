# frozen_string_literal: true

module Zaniah
  module UI
    class TextField < Component
      attr_reader :buffer

      def initialize(value = "", placeholder: nil, label: nil, prefix: nil, suffix: nil,
        error: nil, max_length: nil, clearable: false, disabled: false)
        super()
        @buffer = value.is_a?(TextBuffer) ? value : TextBuffer.new(value.to_s.encode(Encoding::UTF_8))
        @placeholder, @label, @prefix, @suffix = placeholder&.to_s, label&.to_s, prefix, suffix
        @error, @max_length, @clearable, @disabled = error&.to_s, max_length&.to_i, !!clearable, !!disabled
      end

      def value = @buffer.to_s
      def focus_handle = @editor&.focus_handle
      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)
      def error(value) = (@error = value&.to_s; self)

      def build(cx)
        @cx = cx
        field = Div.new.flex_row.items_center.gap(cx.theme.spacing[2]).p([6, 10]).min_h(36)
          .bg(cx.theme.colors.surface).border(1)
          .border_color(@error ? cx.theme.colors.danger : cx.theme.colors.border)
          .rounded(cx.theme.radii[:sm]).focus(ring: Ring.new(2, cx.theme.colors.ring, 1))
        field.child(content(@prefix, cx)) if @prefix
        @editor = Text.new(value, size: cx.theme.typography.size_md, color: cx.theme.colors.text)
          .placeholder(@placeholder || "", color: cx.theme.colors.text_muted).style(min_width: 16, flex_grow: 1, flex_basis: 0)
        unless @disabled
          @editor.editable(@buffer).on_change do |text|
            enforce_max_length(text)
            @on_change&.call(value, @cx)
          end
        end
        field.child(@editor)
        field.child(content(@suffix, cx)) if @suffix
        if @clearable && !value.empty? && !@disabled
          field.child(IconButton.new(:close, label: "Clear", size: :sm, variant: :ghost).on_click { clear })
        end
        root = Div.new.gap(cx.theme.spacing[1])
        root.child(Label.new(@label, size: :sm)) if @label
        root.child(field)
        root.child(Label.new(@error, tone: :muted, size: :xs)) if @error
        root.child(Label.new("#{value.grapheme_clusters.length}/#{@max_length}", tone: :muted, size: :xs)) if @max_length
        root
      end

      def clear
        @buffer.delete(0...@buffer.bytesize)
        @on_change&.call(value, @cx)
        @cx&.window&.request_frame
        self
      end

      def tui_cells(*) = "#{@label && "#{@label}: "}[#{value.empty? ? @placeholder : value}]#{@error && " ! #{@error}"}"
      def accessibility_node(_cx) = node(:textbox, label: @label || @placeholder, value: value, states: {disabled: @disabled, invalid: !@error.nil?}, actions: @disabled ? [] : %i[focus set_value])

      protected

      def content(value, cx)
        value.respond_to?(:request_layout) ? value : Label.new(value.to_s, tone: :muted, size: :sm)
      end

      private

      def enforce_max_length(text)
        return unless @max_length && text.grapheme_clusters.length > @max_length
        accepted = text.grapheme_clusters.take(@max_length).join
        @buffer.replace(0...@buffer.bytesize, accepted)
      end
    end

    class TextArea < TextField
      def initialize(value = "", rows: 4, **options)
        super(value, **options)
        @rows = Integer(rows)
        raise ArgumentError, "rows must be positive" unless @rows.positive?
      end

      def build(cx)
        root = super
        root.style(min_height: @rows * cx.theme.typography.size_md * cx.theme.typography.line_height_normal)
        @editor.wrap(:word)
        root
      end

      def accessibility_node(_cx) = node(:textbox, label: @label || @placeholder, value: value, states: {multiline: true, disabled: @disabled, invalid: !@error.nil?}, actions: @disabled ? [] : %i[focus set_value])
    end

    class SearchInput < TextField
      def initialize(value = "", **options)
        super(value, prefix: Icon.new(:search, label: "Search"), clearable: true, **options)
      end

      def accessibility_node(_cx) = node(:searchbox, label: @label || @placeholder || "Search", value: value, states: {disabled: @disabled}, actions: @disabled ? [] : %i[focus set_value])
    end

    class PasswordInput < TextField
      def build(cx)
        root = super
        @editor.secure
        root
      end

      def tui_cells(*) = "#{@label && "#{@label}: "}[#{"*" * value.grapheme_clusters.length}]"
    end

    class NumberInput < TextField
      def initialize(value = "", min: nil, max: nil, step: 1, **options)
        super(value.to_s, **options)
        @min, @max, @step = min&.to_f, max&.to_f, Float(step)
        raise ArgumentError, "number step must be positive" unless @step.positive?
      end

      def number
        Float(value)
      rescue ArgumentError
        nil
      end

      def increment
        replace_number((number || @min || 0) + @step)
      end

      def decrement
        replace_number((number || @min || 0) - @step)
      end

      private

      def replace_number(number)
        number = number.clamp(@min || -Float::INFINITY, @max || Float::INFINITY)
        @buffer.replace(0...@buffer.bytesize, number.to_s.encode(Encoding::UTF_8))
        @on_change&.call(value, @cx)
        @cx&.window&.request_frame
        self
      end
    end

    class TagInput < TextField
      attr_reader :tags

      def initialize(tags = [], separator: ",", **options)
        @tags, @separator = tags.map(&:to_s), separator.to_s
        super("", **options)
        on_change do |text, cx|
          next unless text.include?(@separator)
          additions = text.split(@separator).map(&:strip).reject(&:empty?)
          @tags.concat(additions).uniq!
          @buffer.delete(0...@buffer.bytesize)
          @on_tags_change&.call(@tags.dup.freeze, cx)
        end
      end

      def on_tags_change(&block) = (@on_tags_change = block; self)

      def build(cx)
        root = super
        root.children.unshift(Div.new.flex_row.gap(cx.theme.spacing[1]).children(@tags.map { |tag| Badge.new(tag) })) if root.respond_to?(:children)
        root
      end

      def tui_cells(*) = "#{@tags.map { |tag| "[#{tag}]" }.join(" ")} #{super}"
      def accessibility_node(_cx) = node(:textbox, label: @label || @placeholder || "Tags", value: @tags, states: {disabled: @disabled}, actions: @disabled ? [] : %i[focus set_value])
    end
  end
end
