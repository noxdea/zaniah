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
        @cx, @display_rows = cx, sorted_rows
        header = Div.new.flex_row.h(@row_height).bg(cx.theme.colors.surface)
          .border_b(1).border_color(cx.theme.colors.border).children(@columns.map { |column| header_cell(column, cx) })
        @body = List.new(count: @display_rows.length, estimated_height: @row_height, overscan: 2) { |index| row(index, cx) }
          .h([@height - @row_height, 1].max)
        Div.new.h(@height).overflow_hidden.border(1).border_color(cx.theme.colors.border)
          .rounded(cx.theme.radii[:sm]).child(header).child(@body)
      end

      def tui_cells(*)
        lines = [@columns.map(&:label).join(" | ")]
        @rows.first(20).each { |row| lines << @columns.map { |column| cell_value(row, column.key) }.join(" | ") }
        lines.join("\n")
      end

      def accessibility_node(_cx)
        rows = visible_indices.map do |index|
          row = @display_rows[index]
          Accessibility.node(role: :row, states: {selected: @selection.include?(row_identity(row, index))},
            children: @columns.map { |column| Accessibility.node(role: :cell, label: column.label, value: cell_value(row, column.key)) })
        end
        node(:table, states: {sort_key: @sort_key, sort_direction: @sort_direction}, children: rows)
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
        return @rows.dup unless @sort_key
        result = @rows.each_with_index.sort_by { |(row, index)| [sortable_value(cell_value(row, @sort_key)), index] }.map(&:first)
        @sort_direction == :desc ? result.reverse : result
      end

      def sortable_value(value) = [value.nil? ? 1 : 0, value.is_a?(Numeric) ? 0 : 1, value.is_a?(Numeric) ? value : value.to_s]

      def header_cell(column, cx)
        cell = Div.new.flex_row.items_center.w(@widths[column.key]).p([4, 8]).gap(4)
          .cursor(column.sortable ? :pointer : :arrow)
          .on_click { sort_by(column.key) if column.sortable }
          .child(Label.new("#{column.label}#{sort_marker(column)}", size: :sm).flex_1)
        if column.resizable
          cell.child(Div.new.w(5).h_full.cursor(:resize_horizontal)
            .on_mouse_down { |event, _| @resize = [column.key, event.position.x, @widths[column.key]] }
            .on_drag { |event, context| resize_column(event, context) }
            .on_mouse_up { @resize = nil }.bg(cx.theme.colors.border))
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

      def row(index, cx)
        value = @display_rows.fetch(index)
        identity = row_identity(value, index)
        Div.new.key(identity).flex_row.h(@row_height).bg(@selection.include?(identity) ? cx.theme.colors.selection : "#0000")
          .border_b(1).border_color(cx.theme.colors.border).cursor(:pointer)
          .on_click { |event, context| select_row(identity, index, event, context) }
          .children(@columns.map { |column| cell(value, identity, index, column, cx) })
      end

      def cell(row, identity, index, column, cx)
        value = cell_value(row, column.key)
        content = if @editing == [index, column.key]
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
            begin_edit(index, column, context) if event.click_count >= 2
          end
        end
        cell
      end

      def begin_edit(index, column, cx)
        @editing = [index, column.key]
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
        if @selection_mode == :single
          @selection.replace([identity])
        elsif modifiers.include?("shift") && @selection_anchor
          range = [@selection_anchor, index].min..[@selection_anchor, index].max
          @selection.merge(range.map { |item| row_identity(@display_rows[item], item) })
        elsif (modifiers & %w[cmd ctrl]).any?
          @selection.include?(identity) ? @selection.delete(identity) : @selection.add(identity)
        else
          @selection.replace([identity])
        end
        @selection_anchor = index
        @on_select&.call(@selection.dup.freeze, event, cx)
        cx.window.request_frame
      end

      def row_identity(row, index) = @row_key.arity == 1 ? @row_key.call(row) : @row_key.call(row, index)
      def cell_value(row, key) = row.is_a?(Hash) ? row.fetch(key, row[key.to_s]) : row.respond_to?(key) ? row.public_send(key) : nil
      def visible_indices = @body&.visible_range || (0...[@display_rows&.length || 0, 20].min)
    end

    class DataGrid < Table; end

    class TreeView < Component
      Item = Data.define(:id, :label, :value, :children, :loader, :parent, :depth)
      attr_reader :selected_id, :expanded

      def initialize(items, height: 320, row_height: 28, selected: nil)
        super()
        @source, @height, @row_height = items.to_a, Float(height), Float(row_height)
        raise ArgumentError, "tree dimensions must be positive" unless @height.positive? && @row_height.positive?
        @selected_id, @expanded, @loaded = selected, Set.new, {}
      end

      def on_select(&block) = (@on_select = block; self)
      def on_toggle(&block) = (@on_toggle = block; self)

      def build(cx)
        @cx = cx
        rebuild
        @list = List.new(count: @visible.length, estimated_height: @row_height) { |index| row(@visible[index], index, cx) }.h(@height)
        @list.focusable(context: {in_tree: true}) { |action| tree_action(action) }
      end

      def expand(id) = (toggle(id, true); self)
      def collapse(id) = (toggle(id, false); self)

      def tui_cells(*)
        rebuild
        @visible.map { |item| "#{"  " * item.depth}#{branch(item)} #{item.label}" }.join("\n")
      end

      def accessibility_node(_cx)
        rebuild
        children = @visible.map do |item|
          expandable = expandable?(item)
          Accessibility.node(role: :treeitem, label: item.label,
            states: {level: item.depth + 1, selected: item.id == @selected_id, expanded: expandable ? @expanded.include?(item.id) : nil},
            actions: expandable ? %i[select expand collapse] : [:select])
        end
        node(:tree, children: children)
      end

      private

      def rebuild
        @parents, @items_by_id, @visible = {}, {}, []
        visit(@source, nil, 0, [])
      end

      def visit(items, parent, depth, path)
        items.each_with_index do |source, index|
          item = normalize_item(source, parent, depth, path + [index])
          raise ArgumentError, "duplicate tree item id #{item.id.inspect}" if @items_by_id.key?(item.id)
          @parents[item.id], @items_by_id[item.id] = parent&.id, item
          @visible << item
          visit(children_for(item), item, depth + 1, path + [index]) if @expanded.include?(item.id)
        end
      end

      def normalize_item(source, parent, depth, path)
        if source.is_a?(Hash)
          children = source[:children]
          Item.new(id: source.fetch(:id, path.freeze), label: source.fetch(:label, source[:value]).to_s,
            value: source.fetch(:value, source), children: children.is_a?(Proc) ? [] : Array(children),
            loader: children.is_a?(Proc) ? children : source[:load], parent: parent&.id, depth: depth)
        elsif source.is_a?(Array) && source.length == 2 && source.last.is_a?(Array)
          Item.new(id: path.freeze, label: source.first.to_s, value: source.first, children: source.last, loader: nil, parent: parent&.id, depth: depth)
        else
          Item.new(id: source.respond_to?(:id) ? source.id : path.freeze, label: source.respond_to?(:label) ? source.label.to_s : source.to_s,
            value: source, children: source.respond_to?(:children) ? Array(source.children) : [], loader: nil, parent: parent&.id, depth: depth)
        end
      end

      def children_for(item) = @loaded.fetch(item.id, item.children)
      def expandable?(item) = item.loader || !children_for(item).empty?
      def branch(item) = expandable?(item) ? (@expanded.include?(item.id) ? "▾" : "▸") : " "

      def row(item, index, cx)
        Div.new.key(item.id).h(@row_height).flex_row.items_center.gap(4).p([2, 6])
          .bg(item.id == @selected_id ? cx.theme.colors.selection : "#0000").cursor(:pointer)
          .on_click { |event, context| select(item, index, event, context) }
          .child(Div.new.w(item.depth * 16))
          .child(Button.new(branch(item), size: :sm, variant: :ghost).on_click { |_event, _context| toggle(item.id) })
          .child(Label.new(item.label, size: :sm))
      end

      def select(item, index, event, cx)
        @selected_id, @selected_index = item.id, index
        @on_select&.call(item.value, event, cx)
        cx.window.request_frame
      end

      def toggle(id, value = nil)
        rebuild unless @items_by_id&.key?(id)
        item = @items_by_id[id]
        return false unless item && expandable?(item)
        open = value.nil? ? !@expanded.include?(id) : value
        if open
          @loaded[id] = Array(item.loader.call(item.value)) if item.loader && !@loaded.key?(id)
          @expanded.add(id)
        else
          @expanded.delete(id)
        end
        @on_toggle&.call(id, open)
        @cx&.window&.request_frame
        open
      end

      def tree_action(action)
        rebuild
        @selected_index = @visible.index { |item| item.id == @selected_id } || 0
        item = @visible[@selected_index]
        case action
        when :previous_option then @selected_index = [@selected_index - 1, 0].max
        when :next_option then @selected_index = [@selected_index + 1, @visible.length - 1].min
        when :first then @selected_index = 0
        when :last then @selected_index = @visible.length - 1
        when :expand then return toggle(item.id, true)
        when :collapse
          return toggle(item.id, false) if @expanded.include?(item.id)
          @selected_id = item.parent if item.parent
          @cx.window.request_frame
          return true
        else return false
        end
        selected = @visible[@selected_index]
        @selected_id = selected&.id
        @on_select&.call(selected&.value, nil, @cx)
        @cx.window.request_frame
        true
      end
    end
  end
end
