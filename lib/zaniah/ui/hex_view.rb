# frozen_string_literal: true

module Zaniah
  module UI
    class HexView < Component
      attr_reader :bytes, :selection, :highlights, :body

      def initialize(bytes, bytes_per_row: 16, group: 8, offset_digits: 4, height: 240, row_height: 24)
        super()
        @bytes_per_row, @group, @offset_digits = bytes_per_row, group, offset_digits
        raise ArgumentError, "hex dimensions must be positive integers" unless [bytes_per_row, group, offset_digits].all? { |v| v.is_a?(Integer) && v.positive? }
        @height, @row_height = Float(height), Float(row_height)
        raise ArgumentError, "view dimensions must be finite and positive" unless [@height, @row_height].all? { |v| v.finite? && v.positive? }
        @highlights, @selection = [], 0...0
        self.bytes = bytes
        @body = UniformList.new(count: row_count, row_height: @row_height) { |index| row(index, @cx) }.h(@height)
      end

      def bytes=(value)
        raise ArgumentError, "bytes must be a String" unless value.is_a?(String)
        @bytes = value.b.dup.freeze
        @selection = 0...0
        @highlights = []
        @body.count = row_count if @body
        invalidate
        value
      end

      def highlights=(values)
        @highlights = values.map do |value|
          range = checked_range(value.fetch(:range))
          tone = value.fetch(:tone, :secondary)
          raise ArgumentError, "highlight tone must be primary or secondary" unless %i[primary secondary].include?(tone)
          {range: range, tone: tone}.freeze
        end.freeze
        invalidate
        values
      end

      def on_select(&block) = (@on_select = block; self)
      def on_copy(&block) = (@on_copy = block; self)

      def select(range, cx = @cx)
        @selection = checked_range(range)
        @anchor, @caret = @selection.begin, [@selection.end - 1, @selection.begin].max
        @on_select&.call(@selection, cx)
        invalidate
      end

      def scroll_to_offset(offset)
        raise IndexError, "offset outside bytes" unless offset.is_a?(Integer) && offset.between?(0, @bytes.bytesize - 1)
        @body.scroll_to(offset / @bytes_per_row, align: :nearest)
        invalidate
      end

      def build(cx)
        @cx = cx
        Div.new.h(@height).overflow_hidden.bg(cx.theme.colors.surface).child(@body)
          .focusable(context: {in_hex_view: true}) { |action| hex_action(action) }
      end

      def tui_cells(*)
        visible_indices.map do |index|
          start = index * @bytes_per_row
          values = @bytes.byteslice(start, @bytes_per_row).bytes
          hex = values.each_slice(@group).map { |slice| slice.map { |b| "%02x" % b }.join(" ") }.join("  ")
          "%0*x  %-*s  %s" % [@offset_digits, start, @bytes_per_row * 3 + @bytes_per_row / @group - 1, hex, values.map { |b| printable(b) }.join]
        end.join("\n")
      end

      def accessibility_node(_cx)
        node(:group, label: "Hexadecimal bytes", states: {byte_count: @bytes.bytesize, selection: [@selection.begin, @selection.end]},
          children: visible_indices.map do |i|
            Accessibility.node(role: :text, label: "Offset #{i * @bytes_per_row}", value: @bytes.byteslice(i * @bytes_per_row, @bytes_per_row).unpack1("H*"))
          end, actions: %i[focus select copy])
      end

      private

      def row(index, cx)
        start = index * @bytes_per_row
        values = @bytes.byteslice(start, @bytes_per_row).bytes
        element = Div.new.flex_row.h(@row_height).items_center.gap(8)
          .child(Text.new("%0*x" % [@offset_digits, start], size: cx.theme.typography.size_sm, color: cx.theme.colors.text_muted))
        [false, true].each do |ascii|
          cells = Div.new.flex_row.gap(ascii ? 0 : 2)
          values.each_with_index do |byte, i|
            offset = start + i
            tone = @selection.cover?(offset) ? :primary : @highlights.reverse.find { |h| h[:range].cover?(offset) }&.fetch(:tone)
            cell = Div.new.w(ascii ? 10 : 24).h_full.items_center.justify_center
              .bg(tone == :primary ? cx.theme.colors.selection : tone == :secondary ? cx.theme.colors.accent.with_alpha(0.25) : "#0000")
              .child(Text.new(ascii ? printable(byte) : "%02x" % byte, size: cx.theme.typography.size_sm, color: cx.theme.colors.text))
              .on_mouse_down { |_event, context| @drag_anchor = offset; select(offset...(offset + 1), context) }
              .on_drag { |event, context| extend_drag(event, context) }
              .on_mouse_up { @drag_anchor = nil }
            cells.child(cell)
            cells.child(Spacer.new(6)) if !ascii && (i + 1) % @group == 0 && i + 1 < values.length
          end
          element.child(cells)
        end
        element
      end

      def extend_drag(event, cx)
        return unless @drag_anchor
        # Reuse laid out cells for hit testing so hex and ASCII select the same bytes.
        @body.children.each_with_index do |element, row_index|
          index = @body.visible_range.begin + row_index
          element.children.drop(1).each do |cells|
            byte_index = 0
            cells.children.each do |cell|
              next if cell.is_a?(Spacer)
              if cell.layout_node.bounds.contains?(event.position)
                offset = index * @bytes_per_row + byte_index
                anchor = @drag_anchor
                select([anchor, offset].min...([anchor, offset].max + 1), cx)
                @drag_anchor = anchor
                return
              end
              byte_index += 1
            end
          end
        end
      end

      def hex_action(action)
        return false if @bytes.empty?
        if action == :copy
          return false if @selection.size.zero?
          content = @on_copy ? @on_copy.call(@selection, @cx) : {"text/plain" => @bytes.byteslice(@selection).unpack1("H*").scan(/../).join(" ")}
          @cx.window.write_clipboard([Clipboard::Item.new(content)])
          return true
        end
        caret = @caret || 0
        offset = case action
        when :move_left, :select_left then caret - 1
        when :move_right, :select_right then caret + 1
        when :previous_option, :extend_previous then caret - @bytes_per_row
        when :next_option, :extend_next then caret + @bytes_per_row
        when :first then 0
        when :last then @bytes.bytesize - 1
        when :page_up then caret - [visible_indices.size - 1, 1].max * @bytes_per_row
        when :page_down then caret + [visible_indices.size - 1, 1].max * @bytes_per_row
        when :select_all then select(0...@bytes.bytesize); return true
        else return false
        end.clamp(0, @bytes.bytesize - 1)
        anchor = action.to_s.start_with?("select_", "extend_") ? (@anchor || caret) : offset
        select([anchor, offset].min...([anchor, offset].max + 1))
        @anchor, @caret = anchor, offset
        scroll_to_offset(offset)
        true
      end

      def checked_range(range)
        raise ArgumentError, "selection must be an integer range" unless range.is_a?(Range) && range.begin.is_a?(Integer) && range.end.is_a?(Integer)
        finish = range.end + (range.exclude_end? ? 0 : 1)
        raise RangeError, "range outside bytes" unless range.begin.between?(0, @bytes.bytesize) && finish.between?(range.begin, @bytes.bytesize)
        range.begin...finish
      end
      def invalidate = (@cx&.window&.request_frame; self)
      def printable(byte) = byte.between?(32, 126) ? byte.chr : "."
      def row_count = (@bytes.bytesize.to_f / @bytes_per_row).ceil
      def visible_indices = @body.visible_range || (0...[row_count, 20].min)
    end
  end
end
