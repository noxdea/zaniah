# frozen_string_literal: true

module Zaniah
  module UI
    class Tabs < Component
      attr_reader :selected_index

      def initialize(items, selected: 0)
        super()
        @items, @selected_index = items.to_a, Integer(selected)
        validate_index
      end

      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        @cx = cx
        tabs = @items.each_with_index.map do |(label, _content), index|
          Button.new(label.to_s, size: :sm, variant: index == @selected_index ? :secondary : :ghost)
            .on_click { |event, context| select(index, event, context) }
        end
        Div.new.gap(cx.theme.spacing[2])
          .focusable(context: {in_tabs: true}) { |action| tab_action(action) }
          .child(Div.new.flex_row.gap(cx.theme.spacing[1]).border_b(1).border_color(cx.theme.colors.border).children(tabs))
          .child(@items[@selected_index][1])
      end

      def tui_cells(*) = "#{@items.map.with_index { |(label, _), index| index == @selected_index ? "[#{label}]" : label }.join(" ")}\n#{content_text}"
      def accessibility_node(cx)
        tabs = @items.map.with_index { |(label, _), index| Accessibility.node(role: :tab, label: label, states: {selected: index == @selected_index}, actions: [:select]) }
        node(:group, children: tabs + [Accessibility.node(role: :tabpanel, children: [@items[@selected_index][1].respond_to?(:accessibility_node) ? @items[@selected_index][1].accessibility_node(cx) : nil].compact)])
      end

      private

      def validate_index
        raise ArgumentError, "tabs require at least one item" if @items.empty?
        raise ArgumentError, "selected tab is outside the items" unless @selected_index.between?(0, @items.length - 1)
      end

      def select(index, event, cx)
        return false if index == @selected_index
        @selected_index = index
        @on_change&.call(index, event, cx)
        cx&.window&.request_frame
        true
      end

      def tab_action(action)
        index = case action
        when :previous_option then (@selected_index - 1) % @items.length
        when :next_option then (@selected_index + 1) % @items.length
        when :first then 0
        when :last then @items.length - 1
        else return false
        end
        select(index, nil, @cx)
      end

      def content_text
        content = @items[@selected_index][1]
        content.respond_to?(:tui_cells) ? content.tui_cells : content.respond_to?(:text) ? content.text : ""
      end
    end

    class Collapsible < Component
      def initialize(label, content, open: false)
        super()
        @label, @content, @open = label.to_s, content, !!open
      end

      def on_change(&block) = (@on_change = block; self)
      def open(value = true) = (@open = !!value; self)

      def build(cx)
        identity = @key || object_id
        state = cx.state([:collapsible, identity]) { {open: @open, visible: @open} }
        if state[:open] != @open
          state[:visible] = true if @open
          cx.animator.animate([:collapsible, identity], from: cx.animator.value([:collapsible, identity], @open ? 0.0 : 1.0),
            to: @open ? 1.0 : 0.0, duration: cx.theme.motion.duration_base, easing: @open ? :ease_out : :ease_in) do
            state[:visible] = false unless @open
            cx.window.request_frame
          end
          state[:open] = @open
        end
        progress = cx.animator.value([:collapsible, identity], @open ? 1.0 : 0.0)
        content = Div.new.key([identity, :content]).overflow_hidden.paint_style(opacity: progress).child(@content) if @content && state[:visible]
        Div.new.gap(cx.theme.spacing[1])
          .child(Button.new("#{@open ? "▾" : "▸"} #{@label}", variant: :ghost).w_full
            .on_click { |event, context| toggle(event, context) })
          .child(content)
      end

      def tui_cells(*) = "#{@open ? "[-]" : "[+]"} #{@label}#{@open ? "\n#{content_text}" : ""}"
      def accessibility_node(cx) = node(:button, label: @label, states: {expanded: @open}, children: @open && @content.respond_to?(:accessibility_node) ? [@content.accessibility_node(cx)] : [], actions: [:toggle])

      private

      def toggle(event, cx)
        @open = !@open
        @on_change&.call(@open, event, cx)
        cx.window.request_frame
      end

      def content_text = @content.respond_to?(:tui_cells) ? @content.tui_cells : @content.respond_to?(:text) ? @content.text : ""
    end

    class Accordion < Component
      def initialize(items, multiple: false, open: nil)
        super()
        @items, @multiple = items.to_a, !!multiple
        @open = Array(open || (@multiple ? [] : 0))
      end

      def build(cx)
        Div.new.gap(1).children(@items.map.with_index do |(label, content), index|
          Collapsible.new(label, content, open: @open.include?(index)).key([@key || object_id, index]).on_change do |opened, _event, context|
            if @multiple
              opened ? @open << index : @open.delete(index)
            else
              @open = opened ? [index] : []
            end
            context.window.request_frame
          end
        end)
      end

      def tui_cells(*) = @items.map.with_index { |(label, _), index| "#{@open.include?(index) ? "[-]" : "[+]"} #{label}" }.join("\n")
      def accessibility_node(_cx) = node(:group, children: @items.map.with_index { |(label, _), index| Accessibility.node(role: :button, label: label, states: {expanded: @open.include?(index)}, actions: [:toggle]) })
    end

    class Breadcrumb < Component
      def initialize(items)
        super()
        @items = items.to_a
      end

      def build(cx)
        children = []
        @items.each_with_index do |item, index|
          label, callback = item.is_a?(Array) ? item : [item, nil]
          children << if callback
            Button.new(label.to_s, size: :sm, variant: :ghost).on_click(&callback)
          else
            Label.new(label.to_s, tone: index == @items.length - 1 ? :default : :muted, size: :sm)
          end
          children << Label.new("/", tone: :muted, size: :sm) unless index == @items.length - 1
        end
        Div.new.flex_row.items_center.gap(cx.theme.spacing[1]).children(children)
      end

      def tui_cells(*) = @items.map { |item| item.is_a?(Array) ? item.first : item }.join(" / ")
      def accessibility_node(_cx) = node(:navigation, label: "Breadcrumb", children: @items.map { |item| Accessibility.node(role: :link, label: item.is_a?(Array) ? item.first : item) })
    end

    class Pagination < Component
      attr_reader :page

      def initialize(page: 1, pages:, window: 2)
        super()
        @page, @pages, @window = Integer(page), Integer(pages), Integer(window)
        raise ArgumentError, "pages and page must be positive and page must be in range" unless @pages.positive? && @page.between?(1, @pages)
      end

      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        indices = ([1, @pages] + ((@page - @window)..(@page + @window)).to_a).select { |page| page.between?(1, @pages) }.uniq.sort
        buttons = [Button.new("‹", size: :sm, variant: :ghost).disabled(@page == 1).on_click { change(@page - 1, cx) }]
        previous = nil
        indices.each do |page|
          buttons << Label.new("…", tone: :muted) if previous && page > previous + 1
          buttons << Button.new(page.to_s, size: :sm, variant: page == @page ? :secondary : :ghost).on_click { change(page, cx) }
          previous = page
        end
        buttons << Button.new("›", size: :sm, variant: :ghost).disabled(@page == @pages).on_click { change(@page + 1, cx) }
        Div.new.flex_row.items_center.gap(cx.theme.spacing[1]).children(buttons)
      end

      def tui_cells(*) = "Page #{@page}/#{@pages}"
      def accessibility_node(_cx) = node(:navigation, label: "Pagination", value: @page, actions: %i[previous next])

      private

      def change(page, cx)
        return if page == @page || !page.between?(1, @pages)
        @page = page
        @on_change&.call(page, cx)
        cx.window.request_frame
      end
    end

    class Bar < Component
      def initialize(*children)
        super()
        @children = children.flatten.compact
      end

      def child(value) = (@children << value; self)
      def tui_cells(*) = @children.map { |child| child.respond_to?(:tui_cells) ? child.tui_cells : child.respond_to?(:text) ? child.text : "" }.join(" ")
      def accessibility_node(cx) = node(:toolbar, children: @children.filter_map { |child| child.accessibility_node(cx) if child.respond_to?(:accessibility_node) })
    end

    class Toolbar < Bar
      def build(cx) = Div.new.flex_row.items_center.gap(cx.theme.spacing[1]).p(cx.theme.spacing[1]).bg(cx.theme.colors.surface).children(@children)
    end

    class StatusBar < Bar
      def build(cx) = Div.new.flex_row.items_center.gap(cx.theme.spacing[2]).p([3, 8]).bg(cx.theme.colors.surface).children(@children)
      def accessibility_node(cx) = node(:status, children: @children.filter_map { |child| child.accessibility_node(cx) if child.respond_to?(:accessibility_node) })
    end

    class Sidebar < Bar
      def initialize(*children, width: 240)
        super(*children)
        @width = width
      end

      def build(cx) = Div.new.w(@width).h_full.gap(cx.theme.spacing[1]).p(cx.theme.spacing[2]).bg(cx.theme.colors.surface).children(@children)
      def accessibility_node(cx) = node(:navigation, children: @children.filter_map { |child| child.accessibility_node(cx) if child.respond_to?(:accessibility_node) })
    end
  end
end
