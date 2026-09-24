# frozen_string_literal: true

require "date"

module Zaniah
  module UI
    class Calendar < Component
      WEEKDAYS = %w[Su Mo Tu We Th Fr Sa].freeze
      MONTH_NAMES = Date::MONTHNAMES.compact.freeze

      attr_reader :value, :cursor, :month

      def initialize(value: nil, min: nil, max: nil, range: false, week_start: 0, month_names: MONTH_NAMES)
        super()
        @min, @max = min && date(min), max && date(max)
        raise ArgumentError, "date range is invalid" if @min && @max && @min > @max
        @week_start = Integer(week_start)
        raise ArgumentError, "week_start must be 0..6" unless @week_start.between?(0, 6)
        @month_names = Array(month_names).map(&:to_s).freeze
        raise ArgumentError, "month_names must contain 12 names" unless @month_names.length == 12
        @range = !!range
        @value = normalize_value(value)
        @cursor = @range ? (@value&.first || clamp(Date.today)) : @value
        @month = Date.new(@cursor.year, @cursor.month, 1)
      end

      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        @cx = cx
        root = Div.new.w(324).p(cx.theme.spacing[2]).gap(cx.theme.spacing[1])
          .bg(cx.theme.colors.surface).border(1).border_color(cx.theme.colors.border)
          .rounded(cx.theme.radii[:sm]).focusable(context: {in_calendar: true}) { |action| calendar_action(action) }
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
        heading = Div.new.flex_row.items_center.gap(cx.theme.spacing[1])
          .child(Button.new("‹", size: :sm, variant: :ghost).w(44).h(44).on_click { move_month(-1) })
          .child(Label.new("#{@month_names[@month.month - 1]} #{@month.year}").flex_1)
          .child(Button.new("›", size: :sm, variant: :ghost).w(44).h(44).on_click { move_month(1) })
        root.child(heading)
        root.child(Div.new.flex_row.children(weekday_indices.map do |index|
          Div.new.w(44).items_center.child(Label.new(WEEKDAYS[index], tone: :muted, size: :sm))
        end))
        days.each_slice(7) do |week|
          root.child(Div.new.flex_row.children(week.map { |day| day_cell(day, cx) }))
        end
        root
      end

      def tui_cells(*)
        heading = "#{@month_names[@month.month - 1]} #{@month.year}"
        weekdays = weekday_indices.map { |index| WEEKDAYS[index].center(4) }.join
        weeks = days.each_slice(7).map do |week|
          week.map { |day| day.month == @month.month ? (selected?(day) ? "[#{format('%02d', day.day)}]" : format('%02d', day.day).center(4)) : "    " }.join.rstrip
        end
        ([heading, weekdays] + weeks).join("\n")
      end

      def accessibility_node(_cx)
        node(:grid, label: "#{@month_names[@month.month - 1]} #{@month.year}",
          value: @range ? @value&.map { |day| day&.iso8601 } : @value.iso8601,
          children: days.map do |day|
            Accessibility.node(role: :gridcell, label: day.iso8601, value: day.iso8601,
              states: {selected: selected?(day), focused: day == @cursor,
                disabled: !allowed?(day), outside_month: day.month != @month.month},
              actions: allowed?(day) ? [:select] : [])
          end)
      end

      def accessibility_action(item, action)
        action == :select && select(date(item.value), @cx)
      end

      private

      def date(value)
        return value if value.is_a?(Date)
        Date.iso8601(value.to_s)
      end

      def normalize_value(value)
        return clamp(date(value || Date.today)) unless @range
        return nil if value.nil?
        pair = value.is_a?(Range) ? [value.begin, value.end] : Array(value)
        raise ArgumentError, "range value must have a start and an optional end" unless pair.length == 2
        start, finish = pair.map { |day| day && date(day) }
        raise ArgumentError, "range start is required" unless start
        raise ArgumentError, "range end must not precede start" if finish && finish < start
        [clamp(start), finish && clamp(finish)].freeze
      end

      def clamp(day) = [[day, @min].compact.max, @max].compact.min
      def allowed?(day) = (!@min || day >= @min) && (!@max || day <= @max)
      def weekday_indices = (0...7).map { |index| (index + @week_start) % 7 }

      def days
        offset = (@month.wday - @week_start) % 7
        first = @month - offset
        Array.new(42) { |index| first + index }
      end

      def selected?(day)
        return @value == day unless @range
        return false unless @value
        first, last = @value
        last ? day.between?(first, last) : day == first
      end

      def day_cell(day, cx)
        selected = selected?(day)
        color = day.month == @month.month ? cx.theme.colors.text : cx.theme.colors.text_muted
        color = cx.theme.colors.text_muted unless allowed?(day)
        cell = Div.new.w(44).h(44).items_center.justify_center.rounded(cx.theme.radii[:sm])
          .bg(selected ? cx.theme.colors.accent : day == @cursor ? cx.theme.colors.surface_hover : "#0000")
          .child(Text.new(day.day.to_s.encode(Encoding::UTF_8), color: selected ? cx.theme.colors.accent_text : color))
        cell.on_click { |_event, context| select(day, context) } if allowed?(day)
        cell
      end

      def calendar_action(action)
        case action
        when :previous_day then move_cursor(-1)
        when :next_day then move_cursor(1)
        when :previous_week then move_cursor(-7)
        when :next_week then move_cursor(7)
        when :previous_month then move_month(-1)
        when :next_month then move_month(1)
        when :activate then select(@cursor, @cx)
        else false
        end
      end

      def move_cursor(days)
        @cursor = clamp(@cursor + days)
        @month = Date.new(@cursor.year, @cursor.month, 1)
        @cx&.window&.request_frame
        true
      end

      def move_month(months)
        @cursor = clamp(@cursor >> months)
        @month = Date.new(@cursor.year, @cursor.month, 1)
        @cx&.window&.request_frame
        true
      end

      def select(day, cx)
        return false unless allowed?(day)
        @cursor = day
        @month = Date.new(day.year, day.month, 1)
        @value = if @range
          if @value.nil? || @value.last
            [day, nil].freeze
          else
            first = @value.first
            (day < first ? [day, first] : [first, day]).freeze
          end
        else
          day
        end
        @on_change&.call(@value, cx)
        cx&.window&.request_frame
        true
      end
    end

    class DateRangePicker < Component
      attr_reader :value

      def initialize(value: nil, min: nil, max: nil, week_start: 0, month_names: Calendar::MONTH_NAMES, label: "Date range")
        super()
        @calendar = Calendar.new(value: value, min: min, max: max, range: true,
          week_start: week_start, month_names: month_names)
        @value, @label, @open = @calendar.value, label.to_s, false
        @calendar.on_change do |range, cx|
          @value = range
          @on_change&.call(range, cx)
          @open = false if range&.last
          cx&.window&.request_frame
        end
      end

      def on_change(&block) = (@on_change = block; self)
      def open? = @open

      def build(cx)
        @cx = cx
        root = Div.new.gap(cx.theme.spacing[1]).style(align_self: :start)
          .child(Button.new("#{@label}: #{formatted}", variant: :secondary).h(44).on_click do |_event, context|
            @open = !@open
            context.window.request_frame
          end)
        root.child(@calendar) if @open
        root
      end

      def tui_cells(*) = "#{@label}: [#{formatted}]"

      def accessibility_node(cx)
        node(:combobox, label: @label, value: formatted, states: {expanded: @open},
          children: @open ? [@calendar.accessibility_node(cx)] : [], actions: [:press])
      end

      def accessibility_action(_item, action)
        return false unless action == :press
        @open = !@open
        @cx&.window&.request_frame
        true
      end

      private

      def formatted = @value ? "#{@value.first.iso8601} – #{@value.last&.iso8601 || '…'}" : "Select dates"
    end
  end
end
