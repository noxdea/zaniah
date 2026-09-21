# frozen_string_literal: true

module Zaniah
  module UI
    # A fixed-cell terminal surface. It deliberately bypasses child elements:
    # terminal grids are updated by row and are too dense for an element tree.
    class TerminalView < Element
      ANSI_COLORS = %w[#000000 #800000 #008000 #808000 #000080 #800080 #008080 #c0c0c0
                       #808080 #ff0000 #00ff00 #ffff00 #0000ff #ff00ff #00ffff #ffffff].freeze

      attr_reader :grid, :damage, :cell_width, :cell_height, :selection

      def initialize(grid: nil, cell_width: 8, cell_height: 18, background: "#111318", foreground: "#ddd")
        super()
        @cell_width, @cell_height = Float(cell_width), Float(cell_height)
        raise ArgumentError, "cell dimensions must be positive" unless @cell_width.positive? && @cell_height.positive?
        @background, @foreground = background, foreground
        @damage = nil
        self.grid = grid if grid
      end

      def grid=(value)
        unless value.respond_to?(:cells) && value.respond_to?(:columns) && value.respond_to?(:rows)
          raise ArgumentError, "grid must expose cells, columns, and rows"
        end
        @grid = value
        @damage = 0...value.rows
        value
      end

      def update(value = @grid, damage: nil)
        self.grid = value unless value.equal?(@grid)
        @damage = damage || value.damage || (0...value.rows)
        self
      end

      def select(range)
        # The range addresses cells in row-major order.
        @selection = range && Range === range ? range : nil
        self
      end

      def request_layout(_cx)
        columns = @grid ? @grid.columns : 0
        rows = @grid ? @grid.rows : 0
        @layout_node = Layout::Node.new(style: @style,
          measure: ->(_width, _height) { [columns * @cell_width, rows * @cell_height] })
      end

      def paint(bounds, state, prepaint, cx)
        super
        return self unless @grid

        rows = @damage || (0...@grid.rows)
        rows = [rows.begin, 0].max...[rows.end, @grid.rows].min
        cx.scene.clip(bounds) do
          rows.each { |row| paint_row(row, bounds, cx) }
          paint_cursor(bounds, cx) if @grid.cursor_visible
        end
        @grid.clear_damage if @grid.respond_to?(:clear_damage)
        @damage = nil
        self
      end

      private

      def paint_row(row, bounds, cx)
        cells = @grid.cells.fetch(row)
        column = 0
        while column < cells.length
          cell = cells[column]
          if cell.background
            run = column + 1
            run += 1 while run < cells.length && cells[run].background == cell.background
            cx.scene.quad(bounds.x + column * @cell_width, bounds.y + row * @cell_height,
              (run - column) * @cell_width, @cell_height, color: color(cell.background))
          end
          if @selection&.cover?(row * @grid.columns + column)
            cx.scene.quad(bounds.x + column * @cell_width, bounds.y + row * @cell_height,
              @cell_width, @cell_height, color: "#ffffff33")
          end
          if cell.width != 0 && cell.text != " "
            paint_text(cell.text, cell.foreground || @foreground, bounds, row, column, cx)
          end
          paint_attributes(cell, bounds, row, column, cx)
          column += 1
        end
      end

      def paint_attributes(cell, bounds, row, column, cx)
        attributes = cell.attributes || {}
        return unless cx.scene.respond_to?(:underline)

        x = bounds.x + column * @cell_width
        y = bounds.y + row * @cell_height
        if attributes[:underline]
          thickness = attributes[:underline] == 2 ? 2 : 1
          cx.scene.underline(x, y + @cell_height - 2, @cell_width, color: color(cell.foreground || @foreground), thickness: thickness)
        end
        if attributes[:strikethrough]
          cx.scene.underline(x, y + @cell_height * 0.52, @cell_width,
            color: color(cell.foreground || @foreground))
        end
      end

      def paint_text(text, tint, bounds, row, column, cx)
        return unless cx.text_system
        line = cx.text_system.layout_line(text, size: @cell_height * 0.78)
        cx.text_system.paint_line(cx.scene, line, x: bounds.x + column * @cell_width,
          y: bounds.y + row * @cell_height + @cell_height * 0.82, color: color(tint))
      end

      def paint_cursor(bounds, cx)
        x, y = @grid.cursor_x, @grid.cursor_y
        cx.scene.layer(Scene::LAYER_SELECTION) do
          cx.scene.quad(bounds.x + x * @cell_width, bounds.y + y * @cell_height,
            @cell_width, @cell_height, color: "#ffffff55")
        end
      end

      def color(value)
        return value if value.is_a?(String)
        return "##{value.map { |part| format("%02x", part) }.join}" if value.is_a?(Array)
        return ANSI_COLORS.fetch(value, @foreground) if value.is_a?(Integer)
        @foreground
      end
    end
  end
end
