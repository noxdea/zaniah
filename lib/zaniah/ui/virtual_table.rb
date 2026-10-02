# frozen_string_literal: true

module Zaniah
  module UI
    # Fetches cells only for visible rows; ordering stays with the data source.
    class VirtualTable < Component
      attr_reader :selection, :sort_key, :sort_direction, :body

      def initialize(source, columns:, height: 320, row_height: 24, selection: :single, follow_tail: false)
        super()
        raise ArgumentError, "source must provide count and cell" unless source.respond_to?(:count) && source.respond_to?(:cell)
        raise ArgumentError, "selection must be none, single, or multiple" unless %i[none single multiple].include?(selection)
        @source, @height, @row_height, @selection_mode = source, Float(height), Float(row_height), selection
        raise ArgumentError, "table dimensions must be finite and positive" unless [@height, @row_height].all? { |v| v.finite? && v.positive? }
        @columns = columns.map do |value|
          value = {key: value} unless value.is_a?(Hash)
          column = {width: 120, sortable: true, resizable: true, visible: true, align: :start}.merge(value)
          column[:key] = column.fetch(:key).to_sym
          column[:label] = column.fetch(:label, column[:key].to_s).to_s
          validate_width(column[:width])
          raise ArgumentError, "alignment must be start, center, or end" unless %i[start center end].include?(column[:align])
          column
        end
        raise ArgumentError, "table needs distinct columns" if @columns.empty? || @columns.map { |c| c[:key] }.uniq.size != @columns.size
        @selection, @active_index, @sort_direction = Set.new, 0, :asc
        @follow_tail = !!follow_tail
        @body = UniformList.new(count: @source.count, row_height: @row_height, stick_to_bottom: @follow_tail) { |index| row(index, @cx) }
          .h([@height - @row_height, 1].max)
      end

      def columns = @columns.map { |column| column.dup.freeze }.freeze
      def on_sort(&block) = (@on_sort = block; self)
      def on_select(&block) = (@on_select = block; self)
      def on_columns_change(&block) = (@on_columns_change = block; self)
      def on_row_context_menu(&block) = (@on_row_context_menu = block; self)
      def invalidate = (@cx&.window&.request_frame; self)
      def following_tail? = @follow_tail && @body.at_bottom?

      def scroll_to(index, align: :start)
        @body.count = @source.count
        @body.scroll_to(index, align: align)
        invalidate
      end

      def select(index, event = nil, cx = @cx)
        raise IndexError, "row outside table" unless index.is_a?(Integer) && index.between?(0, @source.count - 1)
        return self if @selection_mode == :none
        @active_index, @active_id = index, identity_at(index)
        modifiers = event&.modifiers&.map(&:to_s) || []
        if @selection_mode == :multiple && modifiers.include?("shift") && @anchor
          @selection.merge(([@anchor, index].min..[@anchor, index].max).map { |i| identity_at(i) })
        elsif @selection_mode == :multiple && (modifiers & %w[cmd ctrl]).any?
          @selection.include?(@active_id) ? @selection.delete(@active_id) : @selection.add(@active_id)
        else
          @selection.replace([@active_id])
        end
        @anchor = index unless modifiers.include?("shift")
        @on_select&.call(index, event, cx)
        invalidate
      end

      def sort_by(key, direction: nil)
        column = @columns.find { |c| c[:key] == key.to_sym }
        return self unless column && column[:sortable]
        next_direction = direction || (@sort_key == column[:key] && @sort_direction == :asc ? :desc : :asc)
        raise ArgumentError, "sort direction must be asc or desc" unless %i[asc desc].include?(next_direction)
        @sort_key, @sort_direction = column[:key], next_direction
        @on_sort&.call(@sort_key, @sort_direction, @cx)
        invalidate
      end

      def resize_column(key, width, cx = @cx)
        validate_width(width)
        find_column(key)[:width] = width
        columns_changed(cx)
      end

      def column_visible(key, visible = true)
        find_column(key)[:visible] = !!visible
        columns_changed(@cx)
      end

      def move_column(key, index)
        raise IndexError, "column outside table" unless index.is_a?(Integer) && index.between?(0, @columns.size - 1)
        column = find_column(key)
        @columns.delete(column)
        @columns.insert(index, column)
        columns_changed(@cx)
      end

      def build(cx)
        @cx = cx
        @body.count = @source.count
        header = Div.new.flex_row.h(@row_height).bg(cx.theme.colors.surface).children(visible_columns.map { |c| header_cell(c, cx) })
        Div.new.h(@height).overflow_hidden.border(1).border_color(cx.theme.colors.border).child(header).child(@body)
          .focusable(context: {in_table: true}) { |action| table_action(action) }
      end

      def tui_cells(*)
        [visible_columns.map { |c| c[:label] }.join(" | "), *visible_indices.map do |index|
          visible_columns.map { |c| display_value(@source.cell(index, c[:key])) }.join(" | ")
        end].join("\n")
      end

      def accessibility_node(_cx)
        header = Accessibility.node(role: :row, children: visible_columns.map do |c|
          Accessibility.node(role: :columnheader, label: c[:label], states: {sort: @sort_key == c[:key] ? @sort_direction : nil}, actions: c[:sortable] ? [:sort] : [])
        end)
        rows = visible_indices.map do |i|
          Accessibility.node(role: :row, id: identity_at(i), states: {selected: @selection.include?(identity_at(i)), row_index: i}, children: visible_columns.map do |c|
            Accessibility.node(role: :cell, label: c[:label], value: display_value(@source.cell(i, c[:key])))
          end)
        end
        node(:table, states: {row_count: @source.count, sort_key: @sort_key, sort_direction: @sort_direction}, children: [header, *rows])
      end

      private

      def row(index, cx)
        colors = @source.respond_to?(:row_style) ? (@source.row_style(index) || {}) : {}
        identity = identity_at(index)
        element = Div.new.key(identity).flex_row.h(@row_height)
          .bg(@selection.include?(identity) ? cx.theme.colors.selection : colors.fetch(:background, "#0000"))
          .on_click { |event, context| select(index, event, context) }
        if @on_row_context_menu
          element.on_mouse_down do |event, context|
            context.window.context_menu(@on_row_context_menu.call(index, context), position: event.position) if event.button == :right
          end
        end
        element.children(visible_columns.map do |column|
          value = @source.cell(index, column[:key])
          content = value.respond_to?(:request_layout) ? value : Text.new(value.nil? ? "…" : value.to_s,
            size: cx.theme.typography.size_sm, color: colors.fetch(:foreground, cx.theme.colors.text), align: column[:align])
          cell = Div.new.w(column[:width]).h_full.p([2, 8]).style(align_items: column[:align]).overflow_hidden.child(content)
          cell.child(Div.new.style(position: :absolute, left: 8, right: 8, top: @row_height / 2, height: 1, background: colors.fetch(:foreground, cx.theme.colors.text))) if colors[:strikethrough]
          cell
        end)
      end

      def header_cell(column, cx)
        marker = @sort_key == column[:key] ? (@sort_direction == :asc ? " ▲" : " ▼") : ""
        cell = Div.new.flex_row.w(column[:width]).h_full.p([2, 8]).child(Label.new(column[:label] + marker, size: :sm).flex_1)
        cell.on_click { sort_by(column[:key]) } if column[:sortable]
        cell.focusable { |action| action == :activate && !!sort_by(column[:key]) } if column[:sortable]
        if column[:resizable]
          cell.child(Div.new.w(5).h_full.bg(cx.theme.colors.border).cursor(:resize_horizontal)
            .on_mouse_down { |event, _| @resize = [event.position.x, column[:width]] }
            .on_drag { |event, context| resize_column(column[:key], [@resize[1] + event.position.x - @resize[0], 40].max, context) if @resize }
            .on_mouse_up { @resize = nil }
            .focusable(context: {in_slider: true}) do |action|
              delta = {decrement: -8, increment: 8, decrement_page: -32, increment_page: 32}[action]
              delta && !!resize_column(column[:key], [column[:width] + delta, 40].max)
            end)
        end
        cell
      end

      def table_action(action)
        count = @source.count
        return false if count.zero?
        if @active_id && identity_at(@active_index.clamp(0, count - 1)) != @active_id
          # ponytail: scan only after reordering; provide source.index_of(id) for large reordered data.
          @active_index = (@source.respond_to?(:index_of) ? @source.index_of(@active_id) : (0...count).find { |i| identity_at(i) == @active_id }) || 0
        end
        index = case action
        when :previous_option, :extend_previous then @active_index - 1
        when :next_option, :extend_next then @active_index + 1
        when :first then 0
        when :last then count - 1
        when :page_up then @active_index - [visible_indices.size - 1, 1].max
        when :page_down then @active_index + [visible_indices.size - 1, 1].max
        when :activate then @active_index
        when :select_all
          return false unless @selection_mode == :multiple
          @selection.replace((0...count).map { |i| identity_at(i) })
          return !!invalidate
        else return false
        end.clamp(0, count - 1)
        @active_index = index
        event = action.to_s.start_with?("extend_") ? Input::MouseDown.new(Point.new(0, 0), :left, ["shift"], 1) : nil
        select(index, event)
        scroll_to(index, align: :nearest)
        true
      end

      def visible_columns = @columns.select { |c| c[:visible] }
      def visible_indices = (@body.visible_range || (0...[@source.count, 20].min)).select { |i| i < @source.count }
      def identity_at(index) = @source.respond_to?(:row_id) ? @source.row_id(index) : index
      def display_value(value) = value.respond_to?(:tui_cells) ? value.tui_cells.to_s : value.to_s
      def find_column(key) = @columns.find { |c| c[:key] == key.to_sym } || raise(KeyError, "unknown column #{key}")
      def validate_width(width)
        raise ArgumentError, "column width must be finite and positive" unless width.is_a?(Numeric) && width.finite? && width.positive?
      end
      def columns_changed(cx)
        @on_columns_change&.call(columns, cx)
        invalidate
      end
    end
  end
end
