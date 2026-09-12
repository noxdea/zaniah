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

      def paint_line(scene, bounds, values, color)
        points = chart_points(bounds, values)
        path = points.map.with_index { |(x, y), index| "#{index.zero? ? "M" : "L"}#{x},#{y}" }.join
        scene.path(path, stroke: color, width: 2)
      end

      def chart_points(bounds, values)
        minimum, maximum = values.minmax
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
        palette = Array(@colors || [cx.theme.colors.accent, cx.theme.colors.info, cx.theme.colors.success, cx.theme.colors.warning])
        canvas = @canvas = Canvas.new do |bounds, context|
          @plot_bounds = bounds.inset(Edges.new(12, 8, 20, 28))
          axes(context.scene, @plot_bounds, cx.theme.colors.border)
          @series.each_with_index { |(_name, values), index| paint_line(context.scene, @plot_bounds, values, palette[index % palette.length]) }
        end.w(@width).h(@height).on_hover { |event, context| show_line_tooltip(event, context) }
          .focusable(context: {in_chart: true}) { |action| chart_action(action, cx) }
        legend = Div.new.flex_row.gap(10).children(@series.keys.each_with_index.map do |name, index|
          Div.new.flex_row.items_center.gap(4).child(Div.new.w(8).h(8).bg(palette[index % palette.length])).child(Label.new(name, size: :xs))
        end)
        Div.new.gap(4).child(canvas).child(legend)
      end

      private

      def axes(scene, bounds, color)
        scene.path("M#{bounds.x},#{bounds.y}V#{bounds.bottom}H#{bounds.right}", stroke: color, width: 1)
      end

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
        palette = Array(@colors || [cx.theme.colors.accent, cx.theme.colors.info, cx.theme.colors.success, cx.theme.colors.warning])
        canvas = @canvas = Canvas.new do |bounds, context|
          @plot_bounds = bounds.inset(Edges.new(12, 8, 20, 28))
          axes(context.scene, @plot_bounds, cx.theme.colors.border)
          paint_bars(context.scene, @plot_bounds, palette)
        end.w(@width).h(@height).on_hover { |event, context| show_line_tooltip(event, context) }
          .focusable(context: {in_chart: true}) { |action| chart_action(action, cx) }
        Div.new.gap(4).child(canvas).child(Label.new(@series.keys.join(" · "), size: :xs))
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
  end
end
