# frozen_string_literal: true

module Zaniah
  module UI
    class Sparkline < Component
      attr_reader :series

      def initialize(values, width: 160, height: 40, color: nil, label: "Trend")
        super()
        @series, @width, @height, @color, @label = {label.to_s => numbers(values)}, Float(width), Float(height), color, label.to_s
        raise ArgumentError, "chart dimensions must be positive" unless @width.positive? && @height.positive?
      end

      def build(cx)
        color = @color || cx.theme.colors.accent
        @canvas = Canvas.new do |bounds, context|
          @plot_bounds = bounds
          paint_line(context.scene, bounds, @series.values.first, color)
        end.w(@width).h(@height).on_hover { |event, context| show_tooltip(event, context) }
          .focusable(context: {in_chart: true}) { |action| chart_action(action, cx) }
      end

      def tui_cells(*) = spark(@series.values.first)
      def focus_handle = @canvas&.focus_handle
      def accessibility_node(_cx) = node(:image, label: @label, value: summary.merge(selected: selected_summary))

      protected

      def numbers(values)
        result = values.to_a.map { |value| Float(value) }
        raise ArgumentError, "chart values must be finite and nonempty" if result.empty? || !result.all?(&:finite?)
        result.freeze
      end

      def paint_line(scene, bounds, values, color, range: nil)
        points = chart_points(bounds, values, range: range)
        path = points.map.with_index { |(x, y), index| "#{index.zero? ? "M" : "L"}#{x},#{y}" }.join
        scene.path(path, stroke: color, width: 2)
      end

      def chart_points(bounds, values, range: nil)
        minimum, maximum = range || values.minmax
        span = maximum == minimum ? 1.0 : maximum - minimum
        step = values.length == 1 ? 0 : bounds.width / (values.length - 1)
        values.map.with_index { |value, index| [bounds.x + index * step, bounds.bottom - (value - minimum) / span * bounds.height] }
      end

      def show_tooltip(event, cx)
        return unless @plot_bounds
        values = @series.values.first
        index = values.length == 1 ? 0 : ((event.position.x - @plot_bounds.x) / @plot_bounds.width * (values.length - 1)).round.clamp(0, values.length - 1)
        cx.window.offer_tooltip("#{@series.keys.first}: #{values[index]}", position: event.position, delay: 0)
      end

      def chart_action(action, cx)
        count = @series.values.map(&:length).max
        return false unless count&.positive?
        @selected_index ||= 0
        @selected_index = case action
        when :previous_option then [@selected_index - 1, 0].max
        when :next_option then [@selected_index + 1, count - 1].min
        when :first then 0
        when :last then count - 1
        else return false
        end
        position = @plot_bounds ? Point.new(@plot_bounds.x + @plot_bounds.width * @selected_index / [count - 1, 1].max, @plot_bounds.y) : Point.new(0, 0)
        cx.window.offer_tooltip(tooltip_at(@selected_index), position: position, delay: 0)
        cx.window.request_frame
        true
      end

      def tooltip_at(index) = @series.map { |name, values| "#{name}: #{values[[index, values.length - 1].min]}" }.join(" · ")
      def selected_summary = @selected_index && tooltip_at(@selected_index)

      def summary
        values = @series.values.flatten
        {minimum: values.min, maximum: values.max, latest: values.last}.freeze
      end

      def spark(values)
        levels = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █]
        minimum, maximum = values.minmax
        span = maximum == minimum ? 1.0 : maximum - minimum
        values.map { |value| levels[((value - minimum) / span * (levels.length - 1)).round] }.join
      end

      def chart_palette(cx)
        palette = Array(@colors || [cx.theme.colors.accent, cx.theme.colors.info, cx.theme.colors.success, cx.theme.colors.warning])
        raise ArgumentError, "chart colors must not be empty" if palette.empty?
        palette
      end

      def chart_legend(entries, palette)
        Div.new.flex_row.gap(10).children(entries.each_with_index.map do |entry, index|
          label = block_given? ? yield(entry) : entry.to_s
          Div.new.flex_row.items_center.gap(4)
            .child(Div.new.w(8).h(8).bg(palette[index % palette.length]))
            .child(Label.new(label, size: :xs))
        end)
      end

      def cartesian_axes(scene, bounds, color)
        divisions = 4
        grid = (1...divisions).flat_map do |index|
          fraction = index.to_f / divisions
          x = bounds.x + bounds.width * fraction
          y = bounds.y + bounds.height * fraction
          ["M#{x},#{bounds.y}V#{bounds.bottom}", "M#{bounds.x},#{y}H#{bounds.right}"]
        end.join
        ticks = (1...divisions).flat_map do |index|
          fraction = index.to_f / divisions
          x = bounds.x + bounds.width * fraction
          y = bounds.y + bounds.height * fraction
          ["M#{x},#{bounds.bottom}V#{bounds.bottom - 3}", "M#{bounds.x},#{y}H#{bounds.x + 3}"]
        end.join
        scene.path(grid, stroke: color, width: 0.5)
        scene.path("M#{bounds.x},#{bounds.y}V#{bounds.bottom}H#{bounds.right}", stroke: color, width: 1)
        scene.path(ticks, stroke: color, width: 1)
      end
    end

    class LineChart < Sparkline
      def initialize(series, width: 480, height: 240, colors: nil, label: "Line chart")
        input = series.is_a?(Hash) ? series : {label => series}
        super(input.values.first, width: width, height: height, label: label)
        @series = input.to_h { |name, values| [name.to_s, numbers(values)] }.freeze
        raise ArgumentError, "line chart needs at least one series" if @series.empty?
        @width, @height, @colors, @label = Float(width), Float(height), colors, label.to_s
        raise ArgumentError, "chart dimensions must be positive" unless @width.positive? && @height.positive?
      end

      def build(cx)
        palette = chart_palette(cx)
        range = @series.values.flatten.minmax
        canvas = @canvas = Canvas.new do |bounds, context|
          @plot_bounds = bounds.inset(Edges.new(12, 8, 20, 28))
          cartesian_axes(context.scene, @plot_bounds, cx.theme.colors.border)
          @series.each_with_index do |(_name, values), index|
            paint_line(context.scene, @plot_bounds, values, palette[index % palette.length], range: range)
          end
        end.w(@width).h(@height).on_hover { |event, context| show_line_tooltip(event, context) }
          .focusable(context: {in_chart: true}) { |action| chart_action(action, cx) }
        Div.new.gap(4).child(canvas).child(chart_legend(@series.keys, palette))
      end

      private

      def show_line_tooltip(event, cx)
        return unless @plot_bounds
        text = @series.map do |name, values|
          index = values.length == 1 ? 0 : ((event.position.x - @plot_bounds.x) / @plot_bounds.width * (values.length - 1)).round.clamp(0, values.length - 1)
          "#{name}: #{values[index]}"
        end.join(" · ")
        cx.window.offer_tooltip(text, position: event.position, delay: 0)
      end
    end

    class BarChart < LineChart
      def initialize(series, width: 480, height: 240, colors: nil, label: "Bar chart")
        super
      end

      def build(cx)
        palette = chart_palette(cx)
        @axis_color = cx.theme.colors.border
        canvas = @canvas = Canvas.new do |bounds, context|
          @plot_bounds = bounds.inset(Edges.new(12, 8, 20, 28))
          cartesian_axes(context.scene, @plot_bounds, @axis_color)
          paint_bars(context.scene, @plot_bounds, palette)
        end.w(@width).h(@height).on_hover { |event, context| show_line_tooltip(event, context) }
          .focusable(context: {in_chart: true}) { |action| chart_action(action, cx) }
        Div.new.gap(4).child(canvas).child(chart_legend(@series.keys, palette))
      end

      private

      def paint_bars(scene, bounds, palette)
        maximum = [@series.values.flatten.max, 0].max
        minimum = [@series.values.flatten.min, 0].min
        span = maximum == minimum ? 1.0 : maximum - minimum
        count = @series.values.map(&:length).max
        group_width = bounds.width / [count, 1].max
        bar_width = group_width / @series.length * 0.75
        zero = bounds.bottom - (0 - minimum) / span * bounds.height
        @series.values.each_with_index do |values, series_index|
          values.each_with_index do |value, index|
            x = bounds.x + index * group_width + series_index * bar_width
            y = bounds.bottom - (value - minimum) / span * bounds.height
            top, height = [y, zero].minmax.then { |first, last| [first, [last - first, 1].max] }
            scene.path("M#{x},#{top}H#{x + bar_width - 1}V#{top + height}H#{x}Z", fill: palette[series_index % palette.length])
          end
        end
      end
    end

    class PieChart < Sparkline
      attr_reader :slices

      def initialize(data, width: 320, height: 240, colors: nil, label: "Pie chart")
        super([1], width: width, height: height, label: label)
        entries = data.is_a?(Hash) ? data.to_a : data.to_a.each_with_index.map { |value, index| ["#{index + 1}", value] }
        raise ArgumentError, "pie chart needs at least one slice" if entries.empty?

        @slices = entries.map do |name, value|
          value = Float(value)
          raise ArgumentError, "pie values must be finite and nonnegative" unless value.finite? && value >= 0
          [name.to_s.freeze, value].freeze
        end.freeze
        raise ArgumentError, "pie slice labels must be unique" unless @slices.map(&:first).uniq.length == @slices.length
        @values = @slices.map(&:last).freeze
        @total = @values.sum
        raise ArgumentError, "pie chart needs a positive total" unless @total.positive?
        @series = {label.to_s => @values}.freeze
        @width, @height, @colors, @label = Float(width), Float(height), colors, label.to_s
        raise ArgumentError, "chart dimensions must be positive" unless @width.positive? && @height.positive?
      end

      def build(cx)
        palette = chart_palette(cx)

        @canvas = Canvas.new do |bounds, context|
          @plot_bounds = bounds
          paint_slices(context.scene, bounds, palette)
        end.w(@width).h(@height).on_hover { |event, context| show_slice_tooltip(event, context) }
          .focusable(context: {in_chart: true}) { |action| chart_action(action, cx) }
        legend = chart_legend(@slices, palette) do |name, value|
          "#{name}: #{format("%.1f", value / @total * 100)}%"
        end
        Div.new.gap(4).child(@canvas).child(legend)
      end

      def tui_cells(*) = spark(@values)

      def accessibility_node(_cx)
        categories = @slices.map { |name, value| {label: name, value: value}.freeze }.freeze
        node(:image, label: @label, value: {total: @total, categories: categories, selected: selected_summary}.freeze)
      end

      protected

      def tooltip_at(index)
        name, value = @slices.fetch(index)
        "#{name}: #{value}"
      end

      private

      def paint_slices(scene, bounds, palette)
        cx, cy = bounds.x + bounds.width / 2, bounds.y + bounds.height / 2
        radius = [bounds.width, bounds.height].min / 2
        angle = -Math::PI / 2
        @slices.each_with_index do |(_name, value), index|
          next if value.zero?

          finish = angle + Math::PI * 2 * value / @total
          scene.path(slice_path(cx, cy, radius, angle, finish), fill: palette[index % palette.length])
          angle = finish
        end
      end

      def slice_path(cx, cy, radius, start, finish)
        if finish - start >= Math::PI * 2 - 1e-10
          "M#{cx},#{cy - radius} A#{radius},#{radius} 0 1 1 #{cx},#{cy + radius} A#{radius},#{radius} 0 1 1 #{cx},#{cy - radius} Z"
        else
          sx, sy = polar(cx, cy, radius, start)
          ex, ey = polar(cx, cy, radius, finish)
          large = finish - start > Math::PI ? 1 : 0
          "M#{cx},#{cy} L#{sx},#{sy} A#{radius},#{radius} 0 #{large} 1 #{ex},#{ey} Z"
        end
      end

      def polar(cx, cy, radius, angle) = [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius]

      def show_slice_tooltip(event, cx)
        return unless @plot_bounds

        center_x = @plot_bounds.x + @plot_bounds.width / 2
        center_y = @plot_bounds.y + @plot_bounds.height / 2
        angle = (Math.atan2(event.position.y - center_y, event.position.x - center_x) + Math::PI / 2) % (Math::PI * 2)
        target = angle / (Math::PI * 2) * @total
        index = @values.each_index.find do |candidate|
          target -= @values[candidate]
          target < 0
        end || @values.rindex(&:positive?)
        @selected_index = index
        cx.window.offer_tooltip(tooltip_at(index), position: event.position, delay: 0)
      end
    end

    class DonutChart < PieChart
      def initialize(data, **options)
        super
        @inner_radius = 0.56
      end

      private

      def slice_path(cx, cy, radius, start, finish)
        inner = radius * @inner_radius
        if finish - start >= Math::PI * 2 - 1e-10
          "M#{cx},#{cy - radius} A#{radius},#{radius} 0 1 1 #{cx},#{cy + radius} A#{radius},#{radius} 0 1 1 #{cx},#{cy - radius} " \
            "L#{cx},#{cy - inner} A#{inner},#{inner} 0 1 0 #{cx},#{cy + inner} A#{inner},#{inner} 0 1 0 #{cx},#{cy - inner} Z"
        else
          sx, sy = polar(cx, cy, radius, start)
          ex, ey = polar(cx, cy, radius, finish)
          isx, isy = polar(cx, cy, inner, start)
          iex, iey = polar(cx, cy, inner, finish)
          large = finish - start > Math::PI ? 1 : 0
          "M#{sx},#{sy} A#{radius},#{radius} 0 #{large} 1 #{ex},#{ey} L#{iex},#{iey} " \
            "A#{inner},#{inner} 0 #{large} 0 #{isx},#{isy} Z"
        end
      end
    end

    class ScatterChart < Sparkline
      attr_reader :points

      def initialize(series, width: 480, height: 240, colors: nil, label: "Scatter chart")
        input = series.is_a?(Hash) ? series : {label => series}
        raise ArgumentError, "scatter chart needs at least one series" if input.empty?
        @points = input.to_h do |name, values|
          pairs = values.to_a.map do |pair|
            raise ArgumentError, "scatter points must contain x and y" unless pair.respond_to?(:length) && pair.length == 2
            x, y = pair.map { |value| Float(value) }
            raise ArgumentError, "scatter values must be finite" unless x.finite? && y.finite?
            [x, y].freeze
          end
          raise ArgumentError, "scatter series must not be empty" if pairs.empty?
          [name.to_s.freeze, pairs.freeze]
        end.freeze
        super(@points.values.first.map(&:last), width: width, height: height, label: label)
        @series = @points.transform_values { |pairs| pairs.map(&:last).freeze }.freeze
        @width, @height, @colors, @label = Float(width), Float(height), colors, label.to_s
        raise ArgumentError, "chart dimensions must be positive" unless @width.positive? && @height.positive?
      end

      def build(cx)
        palette = chart_palette(cx)

        canvas = @canvas = Canvas.new do |bounds, context|
          @plot_bounds = bounds.inset(Edges.new(12, 8, 20, 28))
          cartesian_axes(context.scene, @plot_bounds, cx.theme.colors.border)
          paint_points(context.scene, @plot_bounds, palette)
        end.w(@width).h(@height).on_hover { |event, context| show_scatter_tooltip(event, context) }
          .focusable(context: {in_chart: true}) { |action| chart_action(action, cx) }
        Div.new.gap(4).child(canvas).child(chart_legend(@points.keys, palette))
      end

      def tui_cells(*) = spark(@series.values.first)

      def accessibility_node(_cx)
        node(:image, label: @label, value: {series: @points, selected: selected_summary}.freeze)
      end

      protected

      def tooltip_at(index)
        @points.map do |name, values|
          x, y = values[[index, values.length - 1].min]
          "#{name}: (#{x}, #{y})"
        end.join(" · ")
      end

      private

      def paint_points(scene, bounds, palette)
        all = @points.values.flatten(1)
        min_x, max_x = all.map(&:first).minmax
        min_y, max_y = all.map(&:last).minmax
        @screen_points = []
        @points.each_with_index do |(name, values), index|
          paths = values.map do |x_value, y_value|
            x = bounds.x + (max_x == min_x ? 0.5 : (x_value - min_x) / (max_x - min_x)) * bounds.width
            y = bounds.bottom - (max_y == min_y ? 0.5 : (y_value - min_y) / (max_y - min_y)) * bounds.height
            @screen_points << [name, x_value, y_value, x, y]
            "M#{x - 3},#{y} A3,3 0 1 0 #{x + 3},#{y} A3,3 0 1 0 #{x - 3},#{y} Z"
          end.join
          scene.path(paths, fill: palette[index % palette.length]) unless paths.empty?
        end
      end

      def show_scatter_tooltip(event, cx)
        nearest = @screen_points.min_by do |(_name, _x_value, _y_value, x, y)|
          (x - event.position.x)**2 + (y - event.position.y)**2
        end
        return unless nearest

        name, x_value, y_value = nearest
        cx.window.offer_tooltip("#{name}: (#{x_value}, #{y_value})", position: event.position, delay: 0)
      end
    end

    class AreaChart < LineChart
      def initialize(series, width: 480, height: 240, colors: nil, stacked: false, label: "Area chart")
        super(series, width: width, height: height, colors: colors, label: label)
        raise ArgumentError, "stacked area series must have equal lengths" if stacked && @series.values.map(&:length).uniq.length > 1
        raise ArgumentError, "stacked area values must be nonnegative" if stacked && @series.values.flatten.any?(&:negative?)
        @stacked = stacked
      end

      def build(cx)
        palette = chart_palette(cx)

        canvas = @canvas = Canvas.new do |bounds, context|
          @plot_bounds = bounds.inset(Edges.new(12, 8, 20, 28))
          cartesian_axes(context.scene, @plot_bounds, cx.theme.colors.border)
          paint_areas(context.scene, @plot_bounds, palette)
        end.w(@width).h(@height).on_hover { |event, context| show_line_tooltip(event, context) }
          .focusable(context: {in_chart: true}) { |action| chart_action(action, cx) }
        Div.new.gap(4).child(canvas).child(chart_legend(@series.keys, palette))
      end

      private

      def paint_areas(scene, bounds, palette)
        count = @series.values.map(&:length).max
        totals = Array.new(count, 0.0)
        if @stacked
          @series.each_value { |values| values.each_with_index { |value, index| totals[index] += value } }
          minimum, maximum = 0.0, totals.max
        else
          minimum, maximum = [0.0, *@series.values.flatten].minmax
        end
        span = maximum == minimum ? 1.0 : maximum - minimum
        y = ->(value) { bounds.bottom - (value - minimum) / span * bounds.height }
        x = ->(index, length) { bounds.x + (length == 1 ? 0.5 : index.to_f / (length - 1)) * bounds.width }
        cumulative = Array.new(count, 0.0)

        @series.each_value.with_index do |values, series_index|
          base = @stacked ? cumulative.dup : Array.new(values.length, 0.0)
          top = values.each_with_index.map { |value, index| @stacked ? (cumulative[index] += value) : value }
          top_x = top.each_index.map { |index| x.call(index, top.length) }
          base_x = base.each_index.map { |index| x.call(index, base.length) }
          path = "M#{base_x.first},#{y.call(base.first)} " \
            "L#{top_x.zip(top).map { |px, value| "#{px},#{y.call(value)}" }.join(" L")} " \
            "L#{base_x.zip(base).reverse.map { |px, value| "#{px},#{y.call(value)}" }.join(" L")} Z"
          scene.path(path, fill: palette[series_index % palette.length])
        end
      end
    end

    class StackedBarChart < BarChart
      private

      def paint_bars(scene, bounds, palette)
        count = @series.values.map(&:length).max
        positive_totals = Array.new(count, 0.0)
        negative_totals = Array.new(count, 0.0)
        @series.each_value do |values|
          values.each_with_index do |value, index|
            value.negative? ? negative_totals[index] += value : positive_totals[index] += value
          end
        end
        minimum, maximum = [negative_totals.min, 0].min, [positive_totals.max, 0].max
        span = maximum == minimum ? 1.0 : maximum - minimum
        y = ->(value) { bounds.bottom - (value - minimum) / span * bounds.height }
        zero = y.call(0)
        group_width = bounds.width / [count, 1].max
        bar_width = group_width * 0.75
        positive = Array.new(count, 0.0)
        negative = Array.new(count, 0.0)

        @series.values.each_with_index do |values, series_index|
          values.each_with_index do |value, index|
            base = value.negative? ? negative[index] - value : positive[index] - value
            finish = base + value
            first, last = [y.call(base), y.call(finish)].minmax
            x = bounds.x + index * group_width + (group_width - bar_width) / 2
            scene.path("M#{x},#{first}H#{x + bar_width}V#{[last, first + 1].max}H#{x}Z", fill: palette[series_index % palette.length])
            value.negative? ? negative[index] = finish : positive[index] = finish
          end
        end
        scene.path("M#{bounds.x},#{zero}H#{bounds.right}", stroke: @axis_color || "#777", width: 1)
      end
    end
  end
end
