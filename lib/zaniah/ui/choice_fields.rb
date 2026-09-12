# frozen_string_literal: true

module Zaniah
  module UI
    class Select < Dropdown
      def initialize(items, label: "Select", value: nil, disabled: false)
        super(label, items: items, value: value)
        @disabled = !!disabled
      end

      def disabled(value = true) = (@disabled = !!value; self)

      def build(cx)
        return Button.new(@value ? @value.to_s : @label, variant: :secondary).disabled if @disabled
        super
      end

      def tui_cells(*) = "#{@label}: [#{@value || "choose"} ▾]"
      def accessibility_node(_cx) = node(:combobox, label: @label, value: @value,
        states: {expanded: false, disabled: @disabled}, actions: @disabled ? [] : [:press])
    end

    class Combobox < Component
      attr_reader :value, :query

      def initialize(items, value: nil, label: "Choose", placeholder: "Type to filter…", disabled: false)
        super()
        @items = normalize_items(items)
        @label, @placeholder, @disabled = label.to_s, placeholder.to_s, !!disabled
        @value = value
        @query = label_for(value).to_s
        @open, @selected_index = false, 0
      end

      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)

      def build(cx)
        @cx = cx
        @matches = @items.select { |label, _| @query.empty? || label.downcase.include?(@query.downcase) }.first(8)
        @selected_index = @selected_index.clamp(0, [@matches.length - 1, 0].max)
        field = TextField.new(@query, label: @label, placeholder: @placeholder, disabled: @disabled)
          .on_change { |text, context| @query = text; @open = true; @selected_index = 0; context&.window&.request_frame }
        root = Div.new.gap(cx.theme.spacing[1]).focusable(context: {in_combobox: true}) { |action| combo_action(action) }.child(field)
        if @open && !@matches.empty? && !@disabled
          root.child(Div.new.p(2).gap(1).bg(cx.theme.colors.surface).border(1).border_color(cx.theme.colors.border)
            .rounded(cx.theme.radii[:sm]).children(@matches.map.with_index do |(label, value), index|
              Button.new(label, size: :sm, variant: index == @selected_index ? :secondary : :ghost).w_full
                .on_click { |event, context| choose(value, label, event, context) }
            end))
        end
        root
      end

      def tui_cells(*) = "#{@label}: [#{@query}█]" + (@open ? "\n" + @matches.map.with_index { |(label, _), index| "#{index == @selected_index ? ">" : " "} #{label}" }.join("\n") : "")
      def accessibility_node(_cx) = node(:combobox, label: @label, value: @value,
        states: {expanded: @open, disabled: @disabled}, actions: @disabled ? [] : %i[focus set_value])

      private

      def normalize_items(items)
        Array(items).map do |item|
          label, value = item.is_a?(Array) ? item : [item, item]
          [label.to_s, value]
        end.freeze
      end

      def label_for(value) = @items.find { |_label, candidate| candidate == value }&.first

      def combo_action(action)
        return false if @disabled
        case action
        when :previous_option then @selected_index = [@selected_index - 1, 0].max
        when :next_option then @selected_index = [@selected_index + 1, @matches.length - 1].min
        when :first then @selected_index = 0
        when :last then @selected_index = [@matches.length - 1, 0].max
        when :choose_option
          match = @matches[@selected_index]
          return false unless match
          return choose(match[1], match[0], nil, @cx)
        when :dismiss then @open = false
        else return false
        end
        @open = true unless action == :dismiss
        @cx.window.request_frame
        true
      end

      def choose(value, label, event, cx)
        @value, @query, @open = value, label, false
        @on_change&.call(value, event, cx)
        cx&.window&.request_frame
        true
      end
    end

    class MultiSelect < Component
      attr_reader :value

      def initialize(items, value: [], label: "Select", disabled: false)
        super()
        @items = Array(items).map { |item| item.is_a?(Array) ? [item.first.to_s, item.last] : [item.to_s, item] }.freeze
        @value, @label, @disabled = Array(value).dup, label.to_s, !!disabled
      end

      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)

      def build(cx)
        selected = @items.select { |_label, value| @value.include?(value) }.map(&:first)
        button = Button.new(selected.empty? ? @label : selected.join(", "), variant: :secondary).disabled(@disabled)
        button.on_click do |_event, context|
          context.window.context_menu(@items.map do |label, value|
            ["#{@value.include?(value) ? "✓ " : "  "}#{label}", -> { toggle(value, context) }]
          end, position: @bounds ? Point.new(@bounds.x, @bounds.bottom) : Point.new(0, 0))
        end
        Div.new.gap(cx.theme.spacing[1]).child(button)
          .child(Div.new.flex_row.style(flex_wrap: :wrap).gap(2).children(selected.map { |label| Badge.new(label) }))
      end

      def tui_cells(*) = "#{@label}: [#{@value.join(", ")}]"
      def accessibility_node(_cx) = node(:listbox, label: @label, value: @value.dup.freeze,
        states: {multiselectable: true, disabled: @disabled}, actions: @disabled ? [] : [:press])

      private

      def toggle(value, cx)
        @value.include?(value) ? @value.delete(value) : @value << value
        @on_change&.call(@value.dup.freeze, nil, cx)
        cx.window.request_frame
      end
    end
  end
end
