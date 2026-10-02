# frozen_string_literal: true

module Zaniah
  module UI
    Completion = Data.define(:range, :items)

    class TextField < Component
      attr_reader :buffer, :status_kind

      def initialize(value = "", placeholder: nil, label: nil, prefix: nil, suffix: nil,
        error: nil, max_length: nil, clearable: false, disabled: false)
        super()
        @buffer = value.is_a?(TextBuffer) ? value : TextBuffer.new(value.to_s.encode(Encoding::UTF_8))
        @placeholder, @label, @prefix, @suffix = placeholder&.to_s, label&.to_s, prefix, suffix
        @error, @max_length, @clearable, @disabled = error&.to_s, max_length&.to_i, !!clearable, !!disabled
        @status_kind, @status_message = @error ? :error : :none, @error
      end

      def value = @buffer.to_s
      def focus_handle = @editor&.focus_handle
      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)
      def error(value) = status(value.nil? ? :none : :error, message: value)
      def caret = @pending_selection&.head || @editor&.selection&.head || 0
      def completing? = !!@completion_open

      def status(kind, message: nil)
        raise ArgumentError, "status must be none, success, warning, or error" unless %i[none success warning error].include?(kind)
        @status_kind, @status_message = kind, message&.to_s
        @error = kind == :error ? @status_message : nil
        @cx&.window&.request_frame
        self
      end

      def completion(provider)
        raise ArgumentError, "provider must implement complete(text, caret)" unless provider.nil? || provider.respond_to?(:complete)
        @completion_provider = provider
        @completion_open = false
        self
      end

      # Completion ranges and caret positions are UTF-8 byte offsets, as in TextBuffer.
      def request_completion(caret: self.caret)
        return self unless @completion_provider && !@disabled && !@buffer.composition
        raise ArgumentError, "caret splits a grapheme cluster" unless caret.is_a?(Integer) && caret.between?(0, @buffer.bytesize) && Unicode.grapheme_boundary?(value, caret)
        result = @completion_provider.complete(value, caret)
        if result
          raise ArgumentError, "provider must return Completion or nil" unless result.is_a?(Completion)
          range = result.range
          raise ArgumentError, "completion needs an exclusive byte range" unless range.is_a?(Range) && range.exclude_end? && [range.begin, range.end].all? { |offset| offset.is_a?(Integer) && offset.between?(0, @buffer.bytesize) && Unicode.grapheme_boundary?(value, offset) } && range.begin <= range.end
          raise ArgumentError, "completion items must have string labels and insert text" unless result.items.is_a?(Array) && result.items.all? { |item| item.is_a?(Hash) && item[:label].is_a?(String) && (!item.key?(:insert_text) || item[:insert_text].is_a?(String)) }
        end
        @completion_result, @completion_index = result, 0
        @completion_query = [value, caret]
        if caret != self.caret
          @pending_selection = TextSelection.new(caret)
          @editor.selection = @pending_selection if @editor && @editor.text == value
        end
        @completion_open = result && !result.items.empty?
        @editor&.focus_handle&.context&.[]=(:in_completion, completing?)
        @cx&.window&.request_frame
        self
      end

      def build(cx)
        @cx = cx
        request_completion if completing? && @completion_query != [value, caret]
        @completion_anchor = if @editor&.layout_node&.bounds && completing?
          point = @editor.offset_to_point(caret)
          box = @editor.layout_node.bounds
          Point.new(box.x + point.x, box.y + point.y + 20)
        end
        selection = @pending_selection || @editor&.selection
        @pending_selection = nil
        tone = {success: :success, warning: :warning, error: :danger}[@status_kind]
        status_color = tone && cx.theme.colors.public_send(tone)
        field = Div.new.flex_row.items_center.gap(cx.theme.spacing[2]).p([6, 10]).min_h(36)
          .bg(status_color ? status_color.with_alpha(0.08) : cx.theme.colors.surface).border(1)
          .border_color(status_color || cx.theme.colors.border)
          .rounded(cx.theme.radii[:sm]).focus(ring: Ring.new(2, cx.theme.colors.ring, 1))
        field.tooltip(@status_message) if @status_message
        field.child(content(@prefix, cx)) if @prefix
        @editor = Text.new(value, size: cx.theme.typography.size_md, color: cx.theme.colors.text)
          .placeholder(@placeholder || "", color: cx.theme.colors.text_muted).style(min_width: 16, flex_grow: 1, flex_basis: 0)
        unless @disabled
          @editor.editable(@buffer).on_change do |text|
            enforce_max_length(text)
            request_completion if @completion_provider
            @on_change&.call(value, @cx)
          end
          if selection && [selection.anchor, selection.head].all? { |offset| offset <= @buffer.bytesize && Unicode.grapheme_boundary?(value, offset) }
            @editor.selection = selection
          end
          if @completion_provider
            original_action = @editor.focus_handle.on_action
            original_validate = @editor.focus_handle.validate
            @editor.focus_handle.context[:in_completion] = completing?
            @editor.focus_handle.validate = ->(action) { completion_action?(action) ? true : original_validate.call(action) }
            @editor.focus_handle.on_action = ->(action) { completion_action(action) || original_action.call(action) }
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
        root.child(completion_popover(cx)) if completing?
        root
      end

      def clear
        @buffer.delete(0...@buffer.bytesize)
        @completion_open = false
        @on_change&.call(value, @cx)
        @cx&.window&.request_frame
        self
      end

      def tui_cells(*)
        marker = {success: " ✓", warning: " !", error: " !"}[@status_kind].to_s
        output = "#{@label && "#{@label}: "}[#{value.empty? ? @placeholder : value}]#{marker}#{@status_message && " #{@status_message}"}"
        output += "\n" + @completion_result.items.each_with_index.map { |item, i| "#{i == @completion_index ? ">" : " "} #{item[:label]}" }.join("\n") if completing?
        output
      end
      def accessibility_node(_cx) = node(:textbox, label: @label || @placeholder, value: value,
        states: status_states, actions: @disabled ? [] : %i[focus set_value])

      protected

      def content(value, cx)
        value.respond_to?(:request_layout) ? value : Label.new(value.to_s, tone: :muted, size: :sm)
      end

      def status_states = {disabled: @disabled, invalid: @status_kind == :error, status: @status_kind, description: @status_message, expanded: completing?}

      private

      def completion_action?(action) = completing? && %i[previous_completion next_completion accept_completion dismiss].include?(action)

      def completion_action(action)
        return false unless completion_action?(action)
        case action
        when :previous_completion then @completion_index = [@completion_index - 1, 0].max
        when :next_completion then @completion_index = [@completion_index + 1, @completion_result.items.size - 1].min
        when :accept_completion then return accept_completion(@completion_index)
        when :dismiss then @completion_open = false
        end
        @editor.focus_handle.context[:in_completion] = completing?
        @cx.window.request_frame
        true
      end

      def accept_completion(index)
        item = @completion_result.items.fetch(index)
        replacement = item.fetch(:insert_text, item[:label]).encode(Encoding::UTF_8)
        range = @completion_result.range
        @buffer.replace(range, replacement)
        enforce_max_length(value)
        @pending_selection = TextSelection.new([range.begin + replacement.bytesize, @buffer.bytesize].min)
        @completion_open = false
        @editor.focus_handle.context[:in_completion] = false
        @on_change&.call(value, @cx)
        @cx.window.request_frame
        true
      end

      def completion_popover(cx)
        first = @completion_index / 8 * 8
        items = @completion_result.items.slice(first, 8).each_with_index.map do |item, visible_index|
          i = first + visible_index
          label = item[:detail] ? "#{item[:label]}  #{item[:detail]}" : item[:label]
          button = if item[:ranges] && !item[:ranges].empty?
            HighlightedButton.new(label, ranges: item[:ranges], size: :sm, variant: i == @completion_index ? :secondary : :ghost)
          else
            Button.new(label, size: :sm, variant: i == @completion_index ? :secondary : :ghost)
          end
          button.w_full.on_click { accept_completion(i) }
        end
        anchor = @completion_anchor || Point.new(@bounds&.x || 0, (@bounds&.y || 0) + 36)
        Popover.new(Div.new.gap(1).children(items), anchor: anchor, width: 320, height: items.size * 32 + 24)
          .on_close { completion_action(:dismiss) }
      end

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

      def accessibility_node(_cx) = node(:textbox, label: @label || @placeholder, value: value, states: status_states.merge(multiline: true), actions: @disabled ? [] : %i[focus set_value])
    end

    class SearchInput < TextField
      def initialize(value = "", **options)
        super(value, prefix: Icon.new(:search, label: "Search"), clearable: true, **options)
      end

      def accessibility_node(_cx) = node(:searchbox, label: @label || @placeholder || "Search", value: value, states: status_states, actions: @disabled ? [] : %i[focus set_value])
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
      def accessibility_node(_cx) = node(:textbox, label: @label || @placeholder || "Tags", value: @tags, states: status_states, actions: @disabled ? [] : %i[focus set_value])
    end
  end
end
