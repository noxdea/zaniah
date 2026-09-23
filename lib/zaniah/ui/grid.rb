# frozen_string_literal: true

module Zaniah
  module UI
    # A sparse-data friendly two-axis view. Only cells intersecting the viewport
    # are built; row and column offsets reuse the list Fenwick index.
    class Grid < Component
      Area = Data.define(:rows, :columns)

      attr_reader :selection, :scroll_state, :visible_rows, :visible_columns

      def initialize(rows:, columns:, row_height: 24, column_width: 96,
        frozen_rows: 0, frozen_columns: 0, estimated_row_height: 24,
        estimated_column_width: 96, overscan: 1, &render_cell)
        super()
        raise ArgumentError, "rows and columns must be nonnegative integers" unless [rows, columns].all? { |count| count.is_a?(Integer) && count >= 0 }
        validate_frozen_counts(frozen_rows, frozen_columns, rows, columns)
        raise ArgumentError, "overscan must be a nonnegative integer" unless overscan.is_a?(Integer) && overscan >= 0
        raise ArgumentError, "a cell renderer is required" unless render_cell

        @rows, @columns = rows, columns
        @frozen_rows, @frozen_columns, @overscan = frozen_rows, frozen_columns, overscan
        @row_size, @column_size = size_provider(row_height), size_provider(column_width)
        @row_overrides, @column_overrides = {}, {}
        @hidden_rows, @hidden_columns = {}, {}
        @row_index = List::HeightIndex.new(rows, estimate(estimated_row_height, row_height))
        @column_index = List::HeightIndex.new(columns, estimate(estimated_column_width, column_width))
        @render_cell, @selection, @selection_anchor = render_cell, [], nil
        @scroll_state = ScrollState.new(axis: :both)
        @active_cell = [0, 0]
        @cell_mouse_down = ->(event, context) do
          row, column = cell_at(event.position)
          begin_cell(row, column, event, context) if row && column
        end
        @cell_drag = ->(event, context) { drag_cell(event, context) }
        @cell_mouse_up = ->(*) { @resize = @fill_drag = nil }
      end

      def on_select(&block) = (@on_select = block; self)
      def on_edit(&block) = (@on_edit = block; self)
      def on_fill(&block) = (@on_fill = block; self)
      def on_resize(&block) = (@on_resize = block; self)

      def selection=(areas)
        unless areas.is_a?(Array) && areas.all? { |area| area.is_a?(Area) }
          raise ArgumentError, "selection must be an array of Grid::Area"
        end
        areas.each { |area| validate_area(area) }
        @selection = areas.dup.freeze
        @cx&.window&.request_frame
        @selection
      end

      def set_row_height(index, height)
        validate_axis_index(index, @rows, "row")
        height = validate_size(height)
        @row_overrides[index] = height
        @row_index.update(index, @hidden_rows.key?(index) ? 0 : height)
        @cx&.window&.request_frame
        self
      end

      def set_column_width(index, width)
        validate_axis_index(index, @columns, "column")
        width = validate_size(width)
        @column_overrides[index] = width
        @column_index.update(index, @hidden_columns.key?(index) ? 0 : width)
        @cx&.window&.request_frame
        self
      end

      def hide_row(index)
        hide_rows([index], hidden: true)
      end

      def unhide_row(index)
        hide_rows([index], hidden: false)
      end

      def hide_column(index)
        hide_columns([index], hidden: true)
      end

      def unhide_column(index)
        hide_columns([index], hidden: false)
      end

      def hide_rows(indices, hidden:)
        update_hidden_indices(indices, hidden, @rows, @hidden_rows, @row_index, method(:row_content_size), "row")
      end

      def hide_columns(indices, hidden:)
        update_hidden_indices(indices, hidden, @columns, @hidden_columns, @column_index, method(:column_content_size), "column")
      end

      def row_hidden?(index)
        validate_axis_index(index, @rows, "row")
        @hidden_rows.key?(index)
      end

      def column_hidden?(index)
        validate_axis_index(index, @columns, "column")
        @hidden_columns.key?(index)
      end

      def freeze_panes(rows:, columns:)
        validate_frozen_counts(rows, columns, @rows, @columns)
        @frozen_rows, @frozen_columns = rows, columns
        @cx&.window&.request_frame
        self
      end

      def scroll_to(row:, column:, align: :nearest)
        validate_cell(row, column)
        frozen_width, frozen_height = frozen_size
        x = [@column_index.prefix(column) - frozen_width, 0].max
        y = [@row_index.prefix(row) - frozen_height, 0].max
        @scroll_state.scroll_rect(Bounds.new(x, y, @column_index[column], @row_index[row]), align: align)
        @cx&.window&.request_frame
        self
      end

      def build(cx)
        @cx = cx
        width = dimension(:width, cx.window.content_size.width)
        height = dimension(:height, cx.window.content_size.height)
        refresh_frozen_sizes
        sync_scroll(width, height)
        refresh_visible_sizes(width, height)
        sync_scroll(width, height)
        calculate_visible(width, height)

        root = Div.new.flex_col.overflow_hidden.style(width: width, height: height)
        frozen_height = [@row_index.prefix(@frozen_rows), height].min
        frozen_width = [@column_index.prefix(@frozen_columns), width].min
        if frozen_height.positive?
          root.child(pane_row(width, frozen_height, frozen: true, frozen_width: frozen_width))
        end
        body_height = [height - frozen_height, 0].max
        root.child(pane_row(width, body_height, frozen: false, frozen_width: frozen_width)) if body_height.positive?
        root
          .focusable(context: {in_grid: true}) { |action| grid_action(action) }
          .on_scroll_wheel { |event, context| scroll(event, context) }
      end

      def tui_cells(*)
        "#{@rows}×#{@columns} grid (#{@selection.length} selected ranges)"
      end

      def accessibility_node(_cx)
        node(:table, label: "Grid", states: {rows: @rows, columns: @columns,
          selected: @selection.map { |area| [area.rows, area.columns] }})
      end

      private

      def size_provider(value)
        return value if value.respond_to?(:call)
        ->(_index) { value }
      end

      def validate_frozen_counts(rows, columns, row_count, column_count)
        unless rows.is_a?(Integer) && columns.is_a?(Integer) && rows.between?(0, row_count) && columns.between?(0, column_count)
          raise ArgumentError, "frozen counts must fit the grid"
        end
      end

      def estimate(value, source)
        value = source if !source.respond_to?(:call) && source.is_a?(Numeric)
        validate_size(value)
      end

      def validate_size(value)
        raise ArgumentError, "cell size must be finite and positive" unless value.is_a?(Numeric) && value.finite? && value.positive?
        value.to_f
      end

      def validate_axis_index(index, count, axis)
        raise IndexError, "#{axis} outside grid" unless index.is_a?(Integer) && index.between?(0, count - 1)
      end

      def update_hidden_indices(indices, hidden, count, state, index, unhidden_size, axis)
        raise ArgumentError, "hidden must be true or false" unless hidden == true || hidden == false
        raise ArgumentError, "#{axis} indexes must be an array" unless indices.is_a?(Array)
        indices.each { |item| validate_axis_index(item, count, axis) }

        items = indices.uniq
        restored_sizes = {}
        unless hidden
          items.each { |item| restored_sizes[item] = unhidden_size.call(item) if state.key?(item) }
        end
        changed = false
        items.each do |item|
          next if state.key?(item) == hidden
          if hidden
            state[item] = true
            index.update(item, 0)
          else
            state.delete(item)
            index.update(item, restored_sizes.fetch(item))
          end
          changed = true
        end
        @cx&.window&.request_frame if changed
        self
      end

      def row_size(index)
        return 0 if @hidden_rows.key?(index)
        row_content_size(index)
      end

      def column_size(index)
        return 0 if @hidden_columns.key?(index)
        column_content_size(index)
      end

      def row_content_size(index) = @row_overrides.fetch(index) { validate_size(@row_size.call(index)) }
      def column_content_size(index) = @column_overrides.fetch(index) { validate_size(@column_size.call(index)) }

      def dimension(property, available)
        value = @component_style[property]
        value = value.resolve(available) if value.is_a?(Length)
        value.is_a?(Numeric) ? [value, 0].max : available
      end

      def refresh_frozen_sizes
        @frozen_rows.times { |index| @row_index.update(index, row_size(index)) }
        @frozen_columns.times { |index| @column_index.update(index, column_size(index)) }
      end

      def sync_scroll(width, height)
        frozen_width, frozen_height = frozen_size
        @scroll_state.update(
          content_size: Size.new([@column_index.total - frozen_width, 0].max, [@row_index.total - frozen_height, 0].max),
          viewport_size: Size.new([width - frozen_width, 0].max, [height - frozen_height, 0].max))
      end

      def frozen_size = [@column_index.prefix(@frozen_columns), @row_index.prefix(@frozen_rows)]

      def refresh_visible_sizes(width, height)
        2.times do
          frozen_width, frozen_height = frozen_size
          first_row = @row_index.index_at(frozen_height + @scroll_state.offset.y)
          last_row = @row_index.index_at(frozen_height + @scroll_state.offset.y + [height - frozen_height, 0].max) + 1
          first_column = @column_index.index_at(frozen_width + @scroll_state.offset.x)
          last_column = @column_index.index_at(frozen_width + @scroll_state.offset.x + [width - frozen_width, 0].max) + 1
          row_range = ((first_row - @overscan).clamp(@frozen_rows, @rows))...([last_row + @overscan, @rows].min)
          column_range = ((first_column - @overscan).clamp(@frozen_columns, @columns))...([last_column + @overscan, @columns].min)
          row_range.each { |index| @row_index.update(index, row_size(index)) }
          column_range.each { |index| @column_index.update(index, column_size(index)) }
          sync_scroll(width, height)
        end
      end

      def calculate_visible(width, height)
        frozen_width, frozen_height = frozen_size
        row_start = (@row_index.index_at(frozen_height + @scroll_state.offset.y) - @overscan).clamp(@frozen_rows, @rows)
        row_finish = [@row_index.index_at(frozen_height + @scroll_state.offset.y + [height - frozen_height, 0].max) + 1 + @overscan, @rows].min
        column_start = (@column_index.index_at(frozen_width + @scroll_state.offset.x) - @overscan).clamp(@frozen_columns, @columns)
        column_finish = [@column_index.index_at(frozen_width + @scroll_state.offset.x + [width - frozen_width, 0].max) + 1 + @overscan, @columns].min
        @visible_rows, @visible_columns = row_start...row_finish, column_start...column_finish
      end

      def pane_row(width, height, frozen:, frozen_width:)
        cells = []
        left_width = frozen_width
        right_width = [width - left_width, 0].max
        if frozen
          if left_width.positive?
            cells << pane(left_width, height, rows: 0...@frozen_rows, columns: 0...@frozen_columns,
              x_offset: 0, y_offset: 0, origin_y: 0, frozen: true)
          end
          if right_width.positive?
            cells << pane(right_width, height, rows: 0...@frozen_rows, columns: @visible_columns,
              x_offset: left_width + @scroll_state.offset.x, y_offset: 0, origin_y: 0, frozen: false, left: left_width)
          end
        else
          if left_width.positive?
            cells << pane(left_width, height, rows: @visible_rows, columns: 0...@frozen_columns,
              x_offset: 0, y_offset: frozen_rows_height + @scroll_state.offset.y,
              origin_y: frozen_rows_height, frozen: false)
          end
          if right_width.positive?
            cells << pane(right_width, height, rows: @visible_rows, columns: @visible_columns,
              x_offset: frozen_columns_width + @scroll_state.offset.x,
              y_offset: frozen_rows_height + @scroll_state.offset.y,
              origin_y: frozen_rows_height, frozen: false, left: left_width)
          end
        end
        Div.new.flex_row.h(height).w(width).overflow_hidden.children(cells)
      end

      def pane(width, height, rows:, columns:, x_offset:, y_offset:, origin_y:, frozen:, left: 0)
        children = []
        row_geometry = rows.map { |row| [row, @row_index.prefix(row), @row_index[row]] }
        column_geometry = columns.map { |column| [column, @column_index.prefix(column), @column_index[column]] }
        row_geometry.each do |row, row_origin, row_height|
          row_top = frozen ? row_origin : row_origin - y_offset
          next unless row_height.positive?
          column_geometry.each do |column, column_origin, column_width|
            column_left = frozen ? column_origin : column_origin - x_offset
            next unless column_width.positive?
            next if column_left + column_width <= (frozen ? left : 0) || row_top + row_height <= 0
            next if column_left >= left + width || row_top >= height
            children << cell(row, column, left: column_left, top: row_top + origin_y,
              width: column_width, height: row_height, left_clip: left, frozen: frozen)
          end
        end
        Div.new.style(position: :relative, width: width, height: height, overflow: :hidden).children(children)
      end

      def cell(row, column, left:, top:, width:, height:, left_clip:, frozen:)
        bounds = Bounds.new(left + left_clip, top, width, height)
        content = @render_cell.call(row, column, bounds, @cx)
        plain_text = content.is_a?(String) || content.is_a?(Numeric)
        if plain_text
          text = content.to_s
          text = text.encode(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8 && text.valid_encoding?
          content = Text.new(text,
            size: @cx.theme.typography.size_sm, color: @cx.theme.colors.text)
        end
        if content && !renderable?(content)
          raise TypeError, "grid cell renderer must return a renderable element, String, Numeric, or nil"
        end
        selected = @selection.any? { |area| area.rows.cover?(row) && area.columns.cover?(column) }
        direct_text = (plain_text || content.is_a?(Text)) && !fill_corner?(row, column)
        wrapper = (direct_text ? content : Div.new).style(position: :absolute, left: left, top: top, width: width, height: height,
          overflow: :hidden, background: selected ? @cx.theme.colors.selection : @cx.theme.colors.surface,
          border: 1, border_color: @cx.theme.colors.border, cursor: :pointer)
        wrapper.child(content) if content && !direct_text
        wrapper.on_mouse_down(&@cell_mouse_down)
        wrapper.on_drag(&@cell_drag)
        wrapper.on_mouse_up(&@cell_mouse_up)
        if fill_corner?(row, column)
          wrapper.child(Div.new.w(7).h(7).style(position: :absolute, right: 0, bottom: 0,
            background: @cx.theme.colors.accent, cursor: :crosshair)
            .on_mouse_down { |event, _context| @fill_drag = @selection.last; :capture }
            .on_drag { |event, context| update_fill(event, context) }
            .on_mouse_up { @fill_drag = nil })
        end
        wrapper
      end

      def renderable?(value)
        %i[request_layout prepaint paint].all? { |method| value.respond_to?(method) }
      end

      def fill_corner?(row, column)
        area = @selection.last
        area && row == area.rows.end - 1 && column == area.columns.end - 1
      end

      def begin_cell(row, column, event, context)
        bounds = cell_bounds(row, column)
        @cx.dispatcher.focus(focus_handle, origin: :pointer)
        @on_edit&.call(row, column, event, context) if event.click_count >= 2
        if event.position.x >= bounds.right - 4
          @resize = [:column, column, event.position.x, @column_index[column]]
          return :capture
        elsif event.position.y >= bounds.bottom - 4
          @resize = [:row, row, event.position.y, @row_index[row]]
          return :capture
        end
        @active_cell = [row, column]
        modifiers = event.modifiers.map(&:to_s)
        if modifiers.include?("shift") && @selection_anchor
          set_active_area(@selection_anchor, [row, column], additive: false, context: context)
        elsif (modifiers & %w[cmd ctrl]).any?
          area = Area.new(rows: row...(row + 1), columns: column...(column + 1))
          @selection = (@selection.include?(area) ? @selection - [area] : @selection + [area]).freeze
          @selection_anchor = [row, column]
          notify_select(event, context)
        else
          @selection_anchor = [row, column]
          set_active_area([row, column], [row, column], additive: false, context: context)
        end
        :capture
      end

      def drag_cell(event, context)
        if @resize
          axis, index, origin, size = @resize
          value = validate_size(size + (axis == :row ? event.position.y : event.position.x) - origin)
          axis == :row ? set_row_height(index, value) : set_column_width(index, value)
          @on_resize&.call(axis, index, value, context)
        elsif @selection_anchor
          target_row, target_column = cell_at(event.position)
          set_active_area(@selection_anchor, [target_row || @active_cell[0], target_column || @active_cell[1]], additive: false, context: context)
        end
      end

      def cell_bounds(row, column)
        x = @column_index.prefix(column)
        y = @row_index.prefix(row)
        x -= @scroll_state.offset.x if column >= @frozen_columns
        y -= @scroll_state.offset.y if row >= @frozen_rows
        Bounds.new(@bounds.x + x, @bounds.y + y, @column_index[column], @row_index[row])
      end

      def set_active_area(first, last, additive:, context: nil)
        area = Area.new(rows: [first[0], last[0]].min..([first[0], last[0]].max),
          columns: [first[1], last[1]].min..([first[1], last[1]].max))
        area = Area.new(rows: area.rows.begin...(area.rows.end + 1), columns: area.columns.begin...(area.columns.end + 1))
        @selection = (additive ? @selection + [area] : [area]).freeze
        notify_select(nil, context)
      end

      def notify_select(event, context)
        @on_select&.call(@selection, event, context)
        context&.window&.request_frame
        @cx&.window&.request_frame
      end

      def update_fill(event, context)
        return unless @fill_drag
        row, column = cell_at(event.position)
        return unless row && column
        area = Area.new(rows: [@fill_drag.rows.begin, row].min...([@fill_drag.rows.end - 1, row].max + 1),
          columns: [@fill_drag.columns.begin, column].min...([@fill_drag.columns.end - 1, column].max + 1))
        @on_fill&.call(@fill_drag, area, context)
        context.window.request_frame
      end

      def cell_at(point)
        return [nil, nil] unless @bounds
        x = point.x - @bounds.x
        y = point.y - @bounds.y
        frozen_width, frozen_height = frozen_size
        column = x < frozen_width ? @column_index.index_at(x) : @column_index.index_at(frozen_width + @scroll_state.offset.x + x - frozen_width)
        row = y < frozen_height ? @row_index.index_at(y) : @row_index.index_at(frozen_height + @scroll_state.offset.y + y - frozen_height)
        [row < @rows ? row : nil, column < @columns ? column : nil]
      end

      def scroll(event, context)
        @scroll_state.glide_by(event.delta, animator: context.animator, key: [:grid_scroll, object_id],
          duration: context.theme.motion.reduced? ? 0 : context.theme.motion.duration_slow)
        context.window.request_frame
      end

      def grid_action(action)
        row, column = @active_cell
        next_row, next_column = case action
        when :previous_option then [[row - 1, 0].max, column]
        when :next_option then [[row + 1, @rows - 1].min, column]
        when :previous_column then [row, [column - 1, 0].max]
        when :next_column then [row, [column + 1, @columns - 1].min]
        when :extend_previous then [[row - 1, 0].max, column]
        when :extend_next then [[row + 1, @rows - 1].min, column]
        when :extend_column_previous then [row, [column - 1, 0].max]
        when :extend_column_next then [row, [column + 1, @columns - 1].min]
        when :first then [0, column]
        when :last then [@rows - 1, column]
        when :select_all
          return false if @rows.zero? || @columns.zero?
          @selection = [Area.new(rows: 0...@rows, columns: 0...@columns)].freeze
          notify_select(nil, @cx)
          return true
        when :activate
          return false if @rows.zero? || @columns.zero?
          @on_edit&.call(row, column, nil, @cx)
          return true
        else return false
        end
        return false if @rows.zero? || @columns.zero?
        @active_cell = [next_row, next_column]
        if action.to_s.start_with?("extend_")
          @selection_anchor ||= [row, column]
          set_active_area(@selection_anchor, @active_cell, additive: false, context: @cx)
        else
          @selection_anchor = @active_cell
          set_active_area(@active_cell, @active_cell, additive: false, context: @cx)
        end
        scroll_to(row: next_row, column: next_column)
        true
      end

      def validate_area(area)
        ranges = [area.rows, area.columns]
        raise ArgumentError, "selection areas need nonempty half-open integer ranges" unless ranges.all? { |range| range.is_a?(Range) && range.exclude_end? && range.begin.is_a?(Integer) && range.end.is_a?(Integer) && range.begin >= 0 && range.begin < range.end }
        raise ArgumentError, "selection is outside the grid" unless area.rows.end <= @rows && area.columns.end <= @columns
      end

      def validate_cell(row, column)
        raise IndexError, "cell outside grid" unless row.is_a?(Integer) && column.is_a?(Integer) && row.between?(0, @rows - 1) && column.between?(0, @columns - 1)
      end

      def frozen_rows_height = @row_index.prefix(@frozen_rows)
      def frozen_columns_width = @column_index.prefix(@frozen_columns)
    end
  end
end
