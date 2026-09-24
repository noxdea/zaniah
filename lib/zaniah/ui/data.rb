# frozen_string_literal: true

module Zaniah
  module UI
    class Table < Component
      Column = Data.define(:key, :label, :width, :sortable, :resizable, :editable, :render)

      attr_reader :selection, :sort_key, :sort_direction

      def initialize(rows, columns:, height: 320, row_height: 32, selection: :single, row_key: nil)
        super()
        raise ArgumentError, "selection must be none, single, or multiple" unless %i[none single multiple].include?(selection)
        @rows, @columns = rows.to_a, columns.map { |column| normalize_column(column) }
        raise ArgumentError, "table needs at least one column" if @columns.empty?
        @height, @row_height, @selection_mode = Float(height), Float(row_height), selection
        raise ArgumentError, "table dimensions must be positive" unless @height.positive? && @row_height.positive?
        @row_key = row_key || ->(_row, index) { index }
        @widths = @columns.to_h { |column| [column.key, Float(column.width)] }
        @selection, @sort_key, @sort_direction = Set.new, nil, :asc
      end

      def on_sort(&block) = (@on_sort = block; self)
      def on_select(&block) = (@on_select = block; self)
      def on_edit(&block) = (@on_edit = block; self)
      def on_copy(&block) = (@on_copy = block; self)
      def on_paste(&block) = (@on_paste = block; self)

      def sort_by(key, direction: nil)
        column = @columns.find { |item| item.key == key.to_sym && item.sortable }
        return self unless column
        @sort_direction = direction || (@sort_key == column.key && @sort_direction == :asc ? :desc : :asc)
        raise ArgumentError, "sort direction must be asc or desc" unless %i[asc desc].include?(@sort_direction)
        @sort_key = column.key
        @on_sort&.call(@sort_key, @sort_direction)
        @cx&.window&.request_frame
        self
      end

      def build(cx)
        @cx = cx
        entries = sorted_rows
        @display_rows, @display_identities = entries.map(&:first), entries.map(&:last)
        @active_index = @display_identities.index { |identity| @selection.include?(identity) } if !@selection.empty?
        @active_index = @active_index.to_i.clamp(0, [@display_rows.length - 1, 0].max)
        header = Div.new.flex_row.h(@row_height).bg(cx.theme.colors.surface)
          .border_b(1).border_color(cx.theme.colors.border).children(@columns.map { |column| header_cell(column, cx) })
        @body = List.new(count: @display_rows.length, estimated_height: @row_height, overscan: 2) { |index| row(index, cx) }
          .h([@height - @row_height, 1].max)
        Div.new.h(@height).overflow_hidden.border(1).border_color(cx.theme.colors.border)
          .rounded(cx.theme.radii[:sm]).child(header).child(@body)
          .focusable(context: {in_table: true}, validate: ->(action) { validate_table_action(action) }) { |action| table_action(action) }
      end

      def tui_cells(*)
        lines = [@columns.map(&:label).join(" | ")]
        @rows.first(20).each { |row| lines << @columns.map { |column| cell_value(row, column.key) }.join(" | ") }
        lines.join("\n")
      end

      def accessibility_node(_cx)
        header = Accessibility.node(role: :row, children: @columns.map do |column|
          Accessibility.node(role: :columnheader, label: column.label,
            states: {sort: @sort_key == column.key ? @sort_direction : nil}, actions: column.sortable ? [:sort] : [])
        end)
        rows = visible_indices.map do |index|
          row = @display_rows[index]
          Accessibility.node(role: :row, states: {selected: @selection.include?(identity_at(index))},
            children: @columns.map { |column| Accessibility.node(role: :cell, label: column.label, value: cell_value(row, column.key)) })
        end
        node(:table, states: {sort_key: @sort_key, sort_direction: @sort_direction}, children: [header, *rows])
      end

      private

      def normalize_column(value)
        value = {key: value} if value.is_a?(Symbol) || value.is_a?(String)
        raise ArgumentError, "columns must be hashes or names" unless value.is_a?(Hash)
        key = value.fetch(:key).to_sym
        width = value.fetch(:width, 120)
        raise ArgumentError, "column width must be positive" unless width.is_a?(Numeric) && width.finite? && width.positive?
        Column.new(key: key, label: value.fetch(:label, key.to_s).to_s, width: width,
          sortable: !!value.fetch(:sortable, true), resizable: !!value.fetch(:resizable, true),
          editable: !!value.fetch(:editable, false), render: value[:render])
      end

      def sorted_rows
        entries = @rows.each_with_index.map { |row, index| [row, index, row_identity(row, index)] }
        unless @sort_key
          return entries.map { |row, _index, identity| [row, identity] }
        end
        entries.sort! do |(left, left_index, _), (right, right_index, _)|
          order = sortable_value(cell_value(left, @sort_key)) <=> sortable_value(cell_value(right, @sort_key))
          order = -order if @sort_direction == :desc
          order.zero? ? left_index <=> right_index : order
        end
        entries.map { |row, _index, identity| [row, identity] }
      end

      def sortable_value(value) = [value.nil? ? 1 : 0, value.is_a?(Numeric) ? 0 : 1, value.is_a?(Numeric) ? value : value.to_s]

      def header_cell(column, cx)
        cell = Div.new.flex_row.items_center.w(@widths[column.key]).p([4, 8]).gap(4)
          .cursor(column.sortable ? :pointer : :arrow)
          .on_click { sort_by(column.key) if column.sortable }
          .child(Label.new("#{column.label}#{sort_marker(column)}", size: :sm).flex_1)
        cell.focusable { |action| action == :activate && !!sort_by(column.key) } if column.sortable
        if column.resizable
          cell.child(Div.new.w(5).h_full.cursor(:resize_horizontal)
            .on_mouse_down { |event, _| @resize = [column.key, event.position.x, @widths[column.key]] }
            .on_drag { |event, context| resize_column(event, context) }
            .on_mouse_up { @resize = nil }.bg(cx.theme.colors.border)
            .focusable(context: {in_slider: true}) { |action| resize_action(column.key, action) })
        end
        cell
      end

      def sort_marker(column) = @sort_key == column.key ? (@sort_direction == :asc ? " ▲" : " ▼") : ""

      def resize_column(event, cx)
        return unless @resize
        key, start, width = @resize
        @widths[key] = [width + event.position.x - start, 40].max
        cx.window.request_frame
      end

      def resize_action(key, action)
        delta = {decrement: -8, decrement_page: -32, increment: 8, increment_page: 32}[action]
        return false unless delta
        @widths[key] = [@widths[key] + delta, 40].max
        @cx.window.request_frame
        true
      end

      def row(index, cx)
        value = @display_rows.fetch(index)
        identity = identity_at(index)
        Div.new.key(identity).flex_row.h(@row_height).bg(@selection.include?(identity) ? cx.theme.colors.selection : "#0000")
          .border_b(1).border_color(cx.theme.colors.border).cursor(:pointer)
          .on_click { |event, context| select_row(identity, index, event, context) }
          .children(@columns.map { |column| cell(value, identity, index, column, cx) })
      end

      def cell(row, identity, index, column, cx)
        value = cell_value(row, column.key)
        content = if @editing == [identity, column.key]
          TextField.new(value.to_s).on_change { |text, context| edit(row, index, column, text, context) }
        elsif column.render
          column.render.call(value, row, index)
        else
          Label.new(value.to_s, size: :sm)
        end
        cell = Div.new.w(@widths[column.key]).h_full.p([4, 8]).items_center.child(content)
        if column.editable
          cell.on_click do |event, context|
            select_row(identity, index, event, context)
            begin_edit(identity, column, context) if event.click_count >= 2
          end
        end
        cell
      end

      def begin_edit(identity, column, cx)
        @editing = [identity, column.key]
        cx.window.request_frame
      end

      def edit(row, index, column, value, cx)
        if row.is_a?(Hash)
          key = row.key?(column.key) ? column.key : column.key.to_s
          row[key] = value
        end
        @on_edit&.call(row, column.key, value, index)
        cx&.window&.request_frame
      end

      def select_row(identity, index, event, cx)
        return if @selection_mode == :none
        modifiers = event.modifiers.map(&:to_s)
        select_index(identity, index, modifiers, event, cx)
      end

      def select_index(identity, index, modifiers, event, cx)
        @active_index = index
        if @selection_mode == :single
          @selection.replace([identity])
        elsif modifiers.include?("shift") && @selection_anchor
          range = [@selection_anchor, index].min..[@selection_anchor, index].max
          @selection.merge(range.map { |item| identity_at(item) })
        elsif (modifiers & %w[cmd ctrl]).any?
          @selection.include?(identity) ? @selection.delete(identity) : @selection.add(identity)
        else
          @selection.replace([identity])
        end
        @selection_anchor = index
        @on_select&.call(@selection.dup.freeze, event, cx)
        cx.window.request_frame
      end

      def table_action(action)
        case action
        when :copy
          return false unless @on_copy && !@selection.empty?
          @cx.window.write_clipboard([Clipboard::Item.new(@on_copy.call(selected_areas, @cx))])
          return true
        when :paste
          return false unless @on_paste && !@selection.empty?
          window = @cx.window
          @on_paste.call(selected_areas, window.read_clipboard(types: window.clipboard_types), @cx)
          return true
        end
        return false if @display_rows.empty?
        index = case action
        when :previous_option, :extend_previous then [@active_index - 1, 0].max
        when :next_option, :extend_next then [@active_index + 1, @display_rows.length - 1].min
        when :first then 0
        when :last then @display_rows.length - 1
        when :page_up then [@active_index - visible_indices.size, 0].max
        when :page_down then [@active_index + visible_indices.size, @display_rows.length - 1].min
        when :activate then @active_index
        when :select_all
          return false unless @selection_mode == :multiple
          @selection.replace(@display_identities)
          @on_select&.call(@selection.dup.freeze, nil, @cx)
          @cx.window.request_frame
          return true
        else return false
        end
        @active_index = index
        identity = identity_at(index)
        begin_edit(identity, @columns.find(&:editable), @cx) if action == :activate && @columns.any?(&:editable)
        modifiers = action.to_s.start_with?("extend_") ? ["shift"] : []
        select_index(identity, index, modifiers, nil, @cx) unless @selection_mode == :none
        @body.scroll_to(index, align: :nearest)
        @cx.window.request_frame
        true
      end

      def validate_table_action(action)
        case action
        when :copy then !@selection.empty? if @on_copy
        when :paste then !@selection.empty? if @on_paste
        when :previous_option, :next_option, :extend_previous, :extend_next,
          :first, :last, :page_up, :page_down, :activate then !@display_rows.empty?
        when :select_all then !@display_rows.empty? && @selection_mode == :multiple
        end
      end

      def selected_areas
        selected = @display_identities.each_index.select { |index| @selection.include?(identity_at(index)) }
        selected.chunk_while { |left, right| right == left + 1 }.map do |indices|
          Grid::Area.new(rows: indices.first...(indices.last + 1), columns: 0...@columns.length)
        end.freeze
      end

      def row_identity(row, index) = @row_key.arity == 1 ? @row_key.call(row) : @row_key.call(row, index)
      def identity_at(index) = @display_identities.fetch(index)
      def cell_value(row, key) = row.is_a?(Hash) ? row.fetch(key, row[key.to_s]) : row.respond_to?(key) ? row.public_send(key) : nil
      def visible_indices = @body&.visible_range || (0...[@display_rows&.length || 0, 20].min)
    end

    class DataGrid < Table; end
  end
end
