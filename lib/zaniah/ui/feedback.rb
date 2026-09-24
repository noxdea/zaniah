# frozen_string_literal: true

module Zaniah
  module UI
    class SegmentedControl < Component
      attr_reader :value

      def initialize(options, value: nil)
        super()
        @options = Array(options).map do |option|
          label, item = option.is_a?(Array) ? option : [option, option]
          [label.to_s, item]
        end.freeze
        raise ArgumentError, "segments require at least one option" if @options.empty?
        raise ArgumentError, "segment values must be unique" if @options.map(&:last).uniq.length != @options.length
        @value = value.nil? ? @options.first.last : value
        raise ArgumentError, "selected segment is not an option" unless @options.any? { |_, item| item == @value }
      end

      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        @cx = cx
        root = Div.new.flex_row.items_center.p(2).gap(2).style(align_self: :start).bg(cx.theme.colors.surface)
          .border(1).border_color(cx.theme.colors.border).rounded(cx.theme.radii[:sm])
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
          .focusable(context: {in_tabs: true}) { |action| navigate(action) }
        @options.each do |label, item|
          selected = item == @value
          root.child(Div.new.h(44).p([5, 10]).items_center.rounded(cx.theme.radii[:sm]).cursor(:pointer)
            .bg(selected ? cx.theme.colors.accent : "#0000")
            .on_click { |event, context| select(item, event, context) }
            .child(Text.new(label, color: selected ? cx.theme.colors.accent_text : cx.theme.colors.text)))
        end
        root
      end

      def tui_cells(*) = "[#{@options.map { |label, item| item == @value ? "(#{label})" : label }.join('|')}]"

      def accessibility_node(_cx)
        node(:radiogroup, value: @value, children: @options.map do |label, item|
          Accessibility.node(role: :radio, label: label, value: item,
            states: {checked: item == @value}, actions: [:select])
        end)
      end

      def accessibility_action(item, action)
        return false unless action == :select
        option = @options.find { |label, value| label == item.label && value == item.value }
        option && select(option.last, nil, @cx)
      end

      private

      def navigate(action)
        index = @options.index { |_, item| item == @value }
        target = case action
        when :previous_option then (index - 1) % @options.length
        when :next_option then (index + 1) % @options.length
        when :first then 0
        when :last then @options.length - 1
        else return false
        end
        select(@options[target].last, nil, @cx)
      end

      def select(item, event, cx)
        return false if item == @value
        @value = item
        @on_change&.call(item, event, cx)
        cx&.window&.request_frame
        true
      end
    end

    class Alert < Component
      VARIANTS = %i[info success warning danger].freeze
      attr_reader :title

      def initialize(title, message: nil, variant: :info, action: nil, dismissible: false, live: false)
        super()
        raise ArgumentError, "unknown alert variant" unless VARIANTS.include?(variant)
        @title, @message, @variant = title.to_s, message&.to_s, variant
        @action, @dismissible, @live, @dismissed = action, !!dismissible, !!live, false
      end

      def dismissed? = @dismissed
      def dismiss
        return false unless @dismissible && !@dismissed
        @dismissed = true
        @cx&.window&.request_frame
        true
      end

      def build(cx)
        @cx = cx
        return Div.new.style(display: :none) if @dismissed
        color = @variant == :info ? cx.theme.colors.accent : cx.theme.colors.public_send(@variant)
        body = Div.new.flex_1.gap(cx.theme.spacing[1]).child(Label.new(@title, size: :md))
        body.child(Label.new(@message, tone: :muted, size: :sm)) if @message
        root = Div.new.flex_row.items_center.gap(cx.theme.spacing[2]).p(cx.theme.spacing[3])
          .bg(cx.theme.colors.surface).border(1).border_color(color).rounded(cx.theme.radii[:sm])
          .child(body)
        root.child(@action) if @action
        root.child(IconButton.new(:close, label: "Dismiss", size: :sm, variant: :ghost).w(44).h(44).on_click { dismiss }) if @dismissible
        root
      end

      def tui_cells(*) = @dismissed ? "" : "! #{@title}#{@message ? ": #{@message}" : ""}"

      def accessibility_node(cx)
        return if @dismissed
        children = [@action&.accessibility_node(cx)].compact
        children << Accessibility.node(role: :button, label: "Dismiss", actions: [:press]) if @dismissible
        node(@live ? :alert : :status, label: [@title, @message].compact.join(": "),
          states: {live: @live}, children: children, actions: @dismissible ? [:dismiss] : [])
      end

      def accessibility_action(_node, action) = %i[dismiss press].include?(action) && dismiss
    end
  end
end
