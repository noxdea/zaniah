# frozen_string_literal: true

require "date"

module Zaniah
  module UI
    class DatePicker < Component
      attr_reader :value

      def initialize(value = Date.today, min: nil, max: nil, label: "Date", disabled: false)
        super()
        @value, @min, @max = Date.parse(value.to_s), min && Date.parse(min.to_s), max && Date.parse(max.to_s)
        raise ArgumentError, "date range is invalid" if @min && @max && @min > @max
        @label, @disabled = label.to_s, !!disabled
        @value = clamp(@value)
      end

      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)

      def build(cx)
        @cx = cx
        field = TextField.new(@value.iso8601, label: @label, disabled: @disabled).on_change { |text, context| parse(text, context) }
        Div.new.flex_row.items_center.gap(cx.theme.spacing[1]).focusable(context: {in_slider: true}) { |action| adjust(action) }
          .child(Button.new("‹", variant: :ghost).disabled(@disabled).on_click { change(@value - 1, cx) })
          .child(field.flex_1)
          .child(Button.new("›", variant: :ghost).disabled(@disabled).on_click { change(@value + 1, cx) })
      end

      def tui_cells(*) = "#{@label}: [#{@value.iso8601}]"
      def accessibility_node(_cx) = node(:combobox, label: @label, value: @value.iso8601,
        states: {disabled: @disabled, minimum: @min&.iso8601, maximum: @max&.iso8601}, actions: @disabled ? [] : %i[increment decrement set_value])

      private

      def clamp(value) = [[value, @min].compact.max, @max].compact.min

      def parse(text, cx)
        change(Date.iso8601(text), cx)
      rescue Date::Error
        false
      end

      def adjust(action)
        return false if @disabled
        days = {decrement: -1, decrement_page: -7, increment: 1, increment_page: 7, minimum: @min, maximum: @max}[action]
        return false unless days
        change(days.is_a?(Date) ? days : @value + days, @cx)
      end

      def change(value, cx)
        value = clamp(value)
        return false if value == @value
        @value = value
        @on_change&.call(value, cx)
        cx&.window&.request_frame
        true
      end
    end

    class TimePicker < Component
      attr_reader :value

      def initialize(value = "00:00", step: 15, label: "Time", disabled: false)
        super()
        @step, @label, @disabled = Integer(step), label.to_s, !!disabled
        raise ArgumentError, "time step must be between 1 and 1440 minutes" unless @step.between?(1, 1440)
        @value = parse_minutes(value)
      end

      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)

      def build(cx)
        @cx = cx
        field = TextField.new(formatted, label: @label, disabled: @disabled).on_change { |text, context| parse(text, context) }
        Div.new.flex_row.items_center.gap(cx.theme.spacing[1]).focusable(context: {in_slider: true}) { |action| adjust(action) }
          .child(Button.new("‹", variant: :ghost).disabled(@disabled).on_click { change(@value - @step, cx) })
          .child(field.flex_1)
          .child(Button.new("›", variant: :ghost).disabled(@disabled).on_click { change(@value + @step, cx) })
      end

      def tui_cells(*) = "#{@label}: [#{formatted}]"
      def accessibility_node(_cx) = node(:combobox, label: @label, value: formatted,
        states: {disabled: @disabled}, actions: @disabled ? [] : %i[increment decrement set_value])

      private

      def formatted = format("%02d:%02d", @value / 60, @value % 60)

      def parse_minutes(value)
        match = /\A(\d{1,2}):(\d{2})\z/.match(value.to_s)
        raise ArgumentError, "time must use HH:MM" unless match && match[1].to_i.between?(0, 23) && match[2].to_i.between?(0, 59)
        match[1].to_i * 60 + match[2].to_i
      end

      def parse(text, cx)
        change(parse_minutes(text), cx)
      rescue ArgumentError
        false
      end

      def adjust(action)
        delta = {decrement: -@step, decrement_page: -60, increment: @step, increment_page: 60, minimum: -@value, maximum: 1439 - @value}[action]
        delta && change(@value + delta, @cx)
      end

      def change(value, cx)
        return false if @disabled
        value = Integer(value).clamp(0, 1439)
        return false if value == @value
        @value = value
        @on_change&.call(formatted, cx)
        cx&.window&.request_frame
        true
      end
    end

    class ColorPicker < Component
      DEFAULT_SWATCHES = %w[#2563eb #16a34a #ca8a04 #dc2626 #9333ea #0f172a].freeze
      attr_reader :value

      def initialize(value = "#2563eb", label: "Color", swatches: DEFAULT_SWATCHES, disabled: false)
        super()
        @value, @label, @swatches, @disabled = normalize(value), label.to_s, Array(swatches).map { |color| normalize(color) }.freeze, !!disabled
      end

      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)

      def build(cx)
        preview = Div.new.w(28).h(28).rounded(cx.theme.radii[:sm]).bg(@value).border(1).border_color(cx.theme.colors.border)
        field = TextField.new(@value, label: @label, disabled: @disabled).on_change { |text, context| set(text, context) }
        swatches = @swatches.map do |color|
          Div.new.w(24).h(24).rounded(cx.theme.radii[:sm]).bg(color).border(color == @value ? 2 : 1)
            .border_color(color == @value ? cx.theme.colors.ring : cx.theme.colors.border).cursor(:pointer)
            .focusable(context: {in_button: true}) { |action| action == :activate && set(color, cx) }
            .on_click { |_event, context| set(color, context) }.disabled(@disabled)
        end
        Div.new.gap(cx.theme.spacing[1]).child(Div.new.flex_row.items_center.gap(cx.theme.spacing[2]).child(preview).child(field.flex_1))
          .child(Div.new.flex_row.gap(cx.theme.spacing[1]).children(swatches))
      end

      def tui_cells(*) = "#{@label}: [#{@value}]"
      def accessibility_node(_cx) = node(:combobox, label: @label, value: @value,
        states: {disabled: @disabled}, actions: @disabled ? [] : %i[set_value increment decrement])

      private

      def normalize(value)
        color = Color.parse(value)
        channels = color.to_a.map { |channel| (channel * 255).round }
        "#" + channels.first(color.a < 1 ? 4 : 3).map { |channel| format("%02x", channel) }.join
      end

      def set(value, cx)
        return false if @disabled
        value = normalize(value)
        return false if value == @value
        @value = value
        @on_change&.call(value, cx)
        cx&.window&.request_frame
        true
      rescue ArgumentError
        false
      end
    end
  end
end
