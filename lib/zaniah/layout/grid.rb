# frozen_string_literal: true

module Zaniah
  module Layout
    module GridLayout
      private

      def layout_grid_children(node, content, children)
        children = children.reject { |child| child.style[:display] == :none && hide(child, node.bounds.x, node.bounds.y) }
        columns = Array(node.style[:grid_template_columns]).flatten
        columns = [:auto] if columns.empty?
        parsed = children.map do |child|
          column, column_span = grid_placement(child.style[:grid_column])
          row, row_span = grid_placement(child.style[:grid_row])
          {node: child, column: column, column_span: column_span || 1, row: row, row_span: row_span || 1}
        end
        column_count = [columns.length, parsed.filter_map { |item| item[:column] && item[:column] + item[:column_span] }.max || 1].max
        columns += Array.new(column_count - columns.length, :auto)
        items = place_grid_items(parsed, column_count)
        row_count = [Array(node.style[:grid_template_rows]).flatten.length,
          items.map { |item| item[:row] + item[:row_span] }.max || 1].max
        rows = Array(node.style[:grid_template_rows]).flatten
        rows += Array.new(row_count - rows.length, :auto)
        column_gap = resolve_length(node.style[:column_gap] || node.style[:gap], content.width, 0)
        row_gap = resolve_length(node.style[:row_gap] || node.style[:gap], content.height, 0)
        natural = items.to_h { |item| [item, natural_size(item[:node], content.width, content.height)] }
        widths = grid_track_sizes(columns, content.width, column_gap,
          grid_intrinsic(items, natural, :column, :column_span, 0, column_count))
        heights = grid_track_sizes(rows, content.height, row_gap,
          grid_intrinsic(items, natural, :row, :row_span, 1, row_count))

        items.each do |item|
          column, row = item.values_at(:column, :row)
          width = widths.slice(column, item[:column_span]).sum + column_gap * (item[:column_span] - 1)
          height = heights.slice(row, item[:row_span]).sum + row_gap * (item[:row_span] - 1)
          x = content.x + widths.take(column).sum + column_gap * column
          y = content.y + heights.take(row).sum + row_gap * row
          layout(item[:node], x, y, width, height, content.width, content.height)
        end
      end

      def grid_placement(value)
        case value
        when nil then [nil, nil]
        when Integer
          raise ArgumentError, "grid positions start at 1" unless value.positive?
          [value - 1, 1]
        when Range
          first, last = Integer(value.begin), Integer(value.end)
          last -= 1 if value.exclude_end?
          raise ArgumentError, "invalid grid range" unless first.positive? && last >= first
          [first - 1, last - first + 1]
        else raise ArgumentError, "grid placement must be an Integer or Range"
        end
      end

      def place_grid_items(items, columns)
        occupied = {}
        cursor = [0, 0]
        items.sort_by { |item| item[:row] && item[:column] ? 0 : item[:row] || item[:column] ? 1 : 2 }.each do |item|
          explicit = item[:row] || item[:column]
          row, column = next_grid_cell(occupied, columns, item, cursor)
          item[:row], item[:column] = row, column
          item[:row_span].times { |dy| item[:column_span].times { |dx| occupied[[row + dy, column + dx]] = true } }
          cursor = column + item[:column_span] >= columns ? [row + 1, 0] : [row, column + item[:column_span]] unless explicit
        end
        items
      end

      def next_grid_cell(occupied, columns, item, cursor)
        column_span, row_span = item.values_at(:column_span, :row_span)
        raise ArgumentError, "grid item span exceeds column count" if column_span > columns
        fixed_row, fixed_column = item.values_at(:row, :column)
        row = fixed_row || (fixed_column ? 0 : cursor[0])
        column = fixed_column || (fixed_row ? 0 : cursor[1])
        loop do
          fits = column + column_span <= columns && row_span.times.all? do |dy|
            column_span.times.none? { |dx| occupied[[row + dy, column + dx]] }
          end
          return [row, column] if fits
          raise ArgumentError, "grid row is already occupied" if fixed_row && fixed_column
          if fixed_column
            row += 1
          else
            column += 1
            row, column = [row + 1, 0] if column + column_span > columns
            raise ArgumentError, "grid row is already occupied" if fixed_row && row > fixed_row
          end
        end
      end

      def grid_intrinsic(items, natural, start_key, span_key, dimension, count)
        values = Array.new(count, 0.0)
        items.each do |item|
          start, span = item.values_at(start_key, span_key)
          wanted = natural.fetch(item)[dimension]
          share = ([wanted - values.slice(start, span).sum, 0].max / span)
          span.times { |index| values[start + index] += share }
        end
        values
      end

      def grid_track_sizes(specs, available, gap, intrinsic)
        total = [available - gap * [specs.length - 1, 0].max, 0].max
        sizes = specs.each_with_index.map { |spec, index| grid_track_min(spec, total, intrinsic[index]) }
        weights = specs.map { |spec| grid_fraction(spec) }
        active = weights.each_index.select { |index| weights[index].positive? }
        remaining = total - sizes.each_index.reject { |index| active.include?(index) }.sum { |index| sizes[index] }
        until active.empty?
          unit = remaining / active.sum { |index| weights[index] }
          constrained = active.select { |index| unit * weights[index] < sizes[index] }
          if constrained.empty?
            active.each { |index| sizes[index] = unit * weights[index] }
            break
          end
          constrained.each { |index| remaining -= sizes[index]; active.delete(index) }
        end
        sizes
      end

      def grid_track_min(spec, available, intrinsic)
        spec = spec.min if spec.is_a?(MinMax)
        return intrinsic if spec.nil? || spec == :auto
        return 0.0 if spec.is_a?(Length) && spec.unit == :fr
        resolve_length(spec, available, 0)
      end

      def grid_fraction(spec)
        spec = spec.max if spec.is_a?(MinMax)
        spec.is_a?(Length) && spec.unit == :fr ? spec.value.to_f : 0.0
      end
    end
  end
end
