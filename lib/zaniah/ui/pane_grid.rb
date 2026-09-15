# frozen_string_literal: true

module Zaniah
  module UI
    class PaneGrid < Component
      Pane = Data.define(:id, :content)
      Resize = Data.define(:axis, :divider, :before, :after)

      attr_reader :pane_ids

      def initialize(panes, columns:, rows:, divider_size: 6, minimum: 24, keyboard_step: 8)
        super()
        @divider_size, @minimum, @keyboard_step = Float(divider_size), Float(minimum), Float(keyboard_step)
        raise ArgumentError, "divider size and keyboard step must be positive and finite" unless
          @divider_size.positive? && @divider_size.finite? && @keyboard_step.positive? && @keyboard_step.finite?
        raise ArgumentError, "pane minimum must be nonnegative and finite" unless @minimum >= 0 && @minimum.finite?

        @columns, @rows, @weights = [], [], {columns: nil, rows: nil}
        replace(panes, columns: columns, rows: rows)
      end

      def on_resize(&block) = (@on_resize = block; self)

      def replace(panes, columns: nil, rows: nil)
        raise Error, "pane-grid callbacks must not re-enter their grid" if @notifying

        next_columns = columns ? normalize_tracks(columns) : @columns
        next_rows = rows ? normalize_tracks(rows) : @rows
        matrix = normalize_panes(panes, next_rows.length, next_columns.length)
        ids = matrix.flatten.compact.map(&:id)
        raise ArgumentError, "pane ids must be unique" unless ids.uniq.length == ids.length

        @weights[:columns] = nil unless next_columns == @columns
        @weights[:rows] = nil unless next_rows == @rows
        @columns, @rows, @panes, @pane_ids = next_columns, next_rows, matrix, ids.freeze
        @measured = nil
        @cx&.window&.request_frame
        self
      end

      def build(cx)
        @cx, @cells, @divider_elements = cx, Array.new(@rows.length) { Array.new(@columns.length) }, {}
        root = Div.new.w_full.h_full.flex_row
        @columns.each_index do |column|
          root.child(apply_track(build_column(column, cx), :columns, @columns[column], @weights[:columns]&.[](column)))
          root.child(divider(:columns, column, cx, focusable: true)) unless column == @columns.length - 1
        end
        root
      end

      def prepaint(bounds, state, cx)
        super
        @measured = {
          columns: @cells.first.map { |cell| cell.layout_node.bounds.width }.freeze,
          rows: @cells.map { |row| row.first.layout_node.bounds.height }.freeze
        }.freeze
      end

      def divider_handle(axis, index)
        index = validate_divider(axis, index)
        @divider_elements&.fetch([axis, index], nil)&.focus_handle
      end

      def track_sizes(axis)
        validate_axis(axis)
        (@measured&.fetch(axis, nil) || []).dup.freeze
      end

      def resize(axis, divider, delta)
        divider = validate_divider(axis, divider)
        sizes = measured(axis)
        change(axis, divider, sizes[divider] + Float(delta), @cx)
      end

      def tui_cells(*)
        @panes.map { |row| row.map { |pane| pane ? text(pane.content) : "" }.join(" │ ") }.join("\n───\n")
      end

      def accessibility_node(cx)
        panes = @panes.each_with_index.flat_map do |row, row_index|
          row.each_with_index.filter_map do |pane, column_index|
            next unless pane
            child = pane.content.accessibility_node(cx) if pane.content.respond_to?(:accessibility_node)
            Accessibility.node(role: :group, label: pane.id.to_s,
              bounds: @cells&.dig(row_index, column_index)&.layout_node&.bounds,
              states: {pane_id: pane.id}, children: [child].compact)
          end
        end
        separators = %i[columns rows].flat_map do |axis|
          (tracks(axis).length - 1).times.map do |index|
            sizes = @measured&.fetch(axis, nil)
            value = sizes && sizes[index] + sizes[index + 1] > 0 ? sizes[index] / (sizes[index] + sizes[index + 1]) : nil
            Accessibility.node(role: :separator, label: "Resize #{axis} #{index + 1} and #{index + 2}", value: value,
              bounds: divider_handle(axis, index)&.bounds,
              states: {axis: axis, orientation: axis == :columns ? :vertical : :horizontal},
              actions: %i[increment decrement minimum maximum])
          end
        end
        node(:group, states: {rows: @rows.length, columns: @columns.length}, children: panes + separators)
      end

      private

      def build_column(column, cx)
        value = Div.new.h_full.flex_col
        @rows.each_index do |row|
          pane = @panes[row][column]
          cell = Div.new.w_full.overflow_hidden
          cell.key([:pane, pane.id]).child(pane.content) if pane
          cell.key([:empty, row, column]) unless pane
          @cells[row][column] = cell
          value.child(apply_track(cell, :rows, @rows[row], @weights[:rows]&.[](row)))
          next if row == @rows.length - 1

          value.child(divider(:rows, row, cx, focusable: column.zero?))
        end
        value
      end

      def divider(axis, index, cx, focusable:)
        vertical = axis == :columns
        value = Div.new.bg(cx.theme.colors.border)
          .style(**(vertical ? {width: @divider_size, height: percent(100), flex_shrink: 0} :
            {width: percent(100), height: @divider_size, flex_shrink: 0}))
          .cursor(vertical ? :resize_horizontal : :resize_vertical)
          .on_drag { |event, context| move(axis, index, event.position, context); :capture }
        if focusable
          value.focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 1))
            .focusable(context: {in_slider: true}) { |action| adjust(axis, index, action) }
          @divider_elements[[axis, index]] = value
        end
        value
      end

      def move(axis, index, point, cx)
        origin = axis == :columns ? @cells.first[index].layout_node.bounds.x : @cells[index].first.layout_node.bounds.y
        coordinate = axis == :columns ? point.x : point.y
        change(axis, index, coordinate - origin - @divider_size / 2, cx)
      end

      def adjust(axis, index, action)
        sizes = measured(axis)
        total = sizes[index] + sizes[index + 1]
        range = resize_range(axis, index, total)
        target = case action
        when :decrement then sizes[index] - @keyboard_step
        when :increment then sizes[index] + @keyboard_step
        when :decrement_page then sizes[index] - @keyboard_step * 4
        when :increment_page then sizes[index] + @keyboard_step * 4
        when :minimum then range.first
        when :maximum then range.last
        else return false
        end
        change(axis, index, target, @cx)
      end

      def change(axis, index, before, cx)
        raise Error, "pane-grid callbacks must not re-enter their grid" if @notifying
        sizes = measured(axis)
        total = sizes[index] + sizes[index + 1]
        return false unless total.positive?

        before = Float(before)
        raise ArgumentError, "pane size must be finite" unless before.finite?
        before = before.clamp(*resize_range(axis, index, total))
        after = total - before
        return false if before == sizes[index]

        original_weights = @weights[axis]
        weights = @weights[axis] ||= sizes.dup
        previous = weights.values_at(index, index + 1)
        pair = previous.sum
        weights[index], weights[index + 1] = pair * before / total, pair * after / total
        begin
          @notifying = true
          @on_resize&.call(Resize.new(axis: axis, divider: index, before: before, after: after), cx)
        rescue StandardError
          weights[index], weights[index + 1] = previous
          @weights[axis] = original_weights
          raise
        ensure
          @notifying = false
        end
        current = sizes.dup
        current[index], current[index + 1] = before, after
        @measured = @measured.merge(axis => current.freeze).freeze
        cx&.window&.request_frame
        true
      end

      def measured(axis)
        sizes = @measured&.fetch(axis, nil)
        raise Error, "pane grid must be laid out before resizing" unless sizes
        sizes
      end

      def resize_range(axis, index, total)
        before_track, after_track = tracks(axis).values_at(index, index + 1)
        before_min = [@minimum, track_minimum(before_track)].max
        after_min = [@minimum, track_minimum(after_track)].max
        lower = [before_min, total - track_maximum(after_track)].max
        upper = [track_maximum(before_track), total - after_min].min
        return [lower, upper] if lower <= upper

        point = measured(axis)[index].clamp(0, total)
        [point, point]
      end

      def track_minimum(track) = track.is_a?(MinMax) ? fixed_track_value(track.min) : 0
      def track_maximum(track) = track.is_a?(MinMax) ? fixed_track_value(track.max) || Float::INFINITY : Float::INFINITY
      def tracks(axis) = axis == :columns ? @columns : @rows

      def apply_track(element, axis, track, weight = nil)
        dimension, minimum, maximum = axis == :columns ? %i[width min_width max_width] : %i[height min_height max_height]
        style = if weight
          {flex_grow: [weight, Float::EPSILON].max, flex_basis: 0,
           minimum => track.is_a?(MinMax) ? track.min : 0}.tap do |values|
            values[maximum] = track.max if track.is_a?(MinMax) && fixed_track_value(track.max)
          end
        elsif track.is_a?(MinMax)
          if track.max.is_a?(Length) && track.max.unit == :fr
            {flex_grow: track.max.value, flex_basis: 0, minimum => track.min}
          else
            {flex_grow: 1, flex_basis: track.min, minimum => track.min, maximum => track.max}
          end
        elsif track.is_a?(Length) && track.unit == :fr
          {flex_grow: track.value, flex_basis: 0, minimum => 0}
        else
          {dimension => track, flex_shrink: 0}
        end
        element.style(**style)
      end

      def normalize_tracks(values)
        values = Array(values)
        raise ArgumentError, "pane grid needs at least one track" if values.empty?
        values.each { |value| validate_track(value) }
        values.dup.freeze
      end

      def validate_track(value, minimum: false)
        if value.is_a?(MinMax)
          raise ArgumentError, "pane minmax minimum must be fixed" if value.min.is_a?(Length) && value.min.unit == :fr
          validate_track(value.min, minimum: true)
          validate_track(value.max)
          lower, upper = fixed_track_value(value.min), fixed_track_value(value.max)
          raise ArgumentError, "pane minmax range is invalid" if lower && upper && upper < lower
          return
        end
        number = value.is_a?(Length) ? value.value : value
        raise TypeError, "pane tracks must be fixed, fractional, or minmax" unless number.is_a?(Numeric)
        raise ArgumentError, "pane track units must be px or fr" if value.is_a?(Length) && !%i[px fr].include?(value.unit)
        number = Float(number)
        valid = minimum ? number >= 0 : number.positive?
        raise ArgumentError, "pane tracks must be finite and #{minimum ? 'nonnegative' : 'positive'}" unless valid && number.finite?
      end

      def normalize_panes(panes, row_count, column_count)
        values = Array(panes)
        raise ArgumentError, "pane rows do not match row tracks" unless values.length == row_count
        values.map do |row|
          row = Array(row)
          raise ArgumentError, "pane columns do not match column tracks" unless row.length == column_count
          row.map do |value|
            next if value.nil?
            pane = if value.is_a?(Pane)
              value
            elsif value.is_a?(Hash)
              Pane.new(id: value.fetch(:id), content: value.fetch(:content))
            elsif value.is_a?(Array) && value.length == 2
              Pane.new(id: value.first, content: value.last)
            else
              raise TypeError, "pane must be a Pane, id/content hash, pair, or nil"
            end
            raise ArgumentError, "pane id must not be nil" if pane.id.nil?
            unless pane.content.respond_to?(:request_layout) && pane.content.respond_to?(:prepaint) && pane.content.respond_to?(:paint)
              raise TypeError, "pane content must be renderable"
            end
            pane
          end.freeze
        end.freeze
      end

      def validate_axis(axis)
        raise ArgumentError, "pane axis must be columns or rows" unless %i[columns rows].include?(axis)
      end

      def validate_divider(axis, index)
        validate_axis(axis)
        index = Integer(index)
        raise IndexError, "pane divider is outside the tracks" unless index.between?(0, tracks(axis).length - 2)
        index
      end

      def fixed_track_value(value)
        Float(value.is_a?(Length) ? value.value : value) unless value.is_a?(Length) && value.unit == :fr
      end

      def text(value) = value.respond_to?(:tui_cells) ? value.tui_cells : value.respond_to?(:text) ? value.text : "pane"
    end
  end
end
