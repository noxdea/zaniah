# frozen_string_literal: true

module Zaniah
  module UI
    class SplitPane < Component
      attr_reader :ratio

      def initialize(first, second, orientation: :horizontal, ratio: 0.5, min: 0.1, max: 0.9)
        super()
        raise ArgumentError, "split orientation must be horizontal or vertical" unless %i[horizontal vertical].include?(orientation)
        @first, @second, @orientation = first, second, orientation
        @min, @max, @ratio = Float(min), Float(max), Float(ratio)
        raise ArgumentError, "split ratio range is invalid" unless 0 <= @min && @min < @max && @max <= 1
        @ratio = @ratio.clamp(@min, @max)
      end

      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        @cx = cx
        horizontal = @orientation == :horizontal
        first = Div.new.style(**{(horizontal ? :width : :height) => percent(@ratio * 100)}).overflow_hidden.child(@first)
        second = Div.new.flex_1.overflow_hidden.child(@second)
        handle = Div.new.style(**{(horizontal ? :width : :height) => 6})
          .bg(cx.theme.colors.border).cursor(horizontal ? :resize_horizontal : :resize_vertical)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 1))
          .focusable(context: {in_slider: true}) { |action| adjust(action) }
          .on_drag { |event, context| drag(event, context) }
        root = Div.new.w_full.h_full.children([first, handle, second])
        horizontal ? root.flex_row : root.flex_col
      end

      def tui_cells(*) = "#{text(@first)} #{@orientation == :horizontal ? "│" : "─"} #{text(@second)}"
      def accessibility_node(cx)
        panes = [@first, @second].map { |pane| pane.accessibility_node(cx) if pane.respond_to?(:accessibility_node) }
        divider = Accessibility.node(role: :separator, value: @ratio,
          states: {orientation: @orientation}, actions: %i[increment decrement])
        node(:group, states: {orientation: @orientation}, children: [panes.first, divider, panes.last].compact)
      end

      private

      def drag(event, cx)
        return false unless @bounds
        size = @orientation == :horizontal ? @bounds.width : @bounds.height
        offset = @orientation == :horizontal ? event.position.x - @bounds.x : event.position.y - @bounds.y
        change(offset / [size, 1].max, cx)
        :capture
      end

      def adjust(action)
        delta = {decrement: -0.02, decrement_page: -0.1, increment: 0.02, increment_page: 0.1, minimum: @min - @ratio, maximum: @max - @ratio}[action]
        delta && change(@ratio + delta, @cx)
      end

      def change(value, cx)
        value = Float(value).clamp(@min, @max)
        return false if value == @ratio
        @ratio = value
        @on_change&.call(value, cx)
        cx&.window&.request_frame
        true
      end

      def text(value) = value.respond_to?(:tui_cells) ? value.tui_cells : value.respond_to?(:text) ? value.text : "pane"
    end

    class Resizable < Component
      attr_reader :width, :height

      def initialize(content, width: 240, height: 160, min_width: 40, min_height: 40, max_width: Float::INFINITY, max_height: Float::INFINITY)
        super()
        @content = content
        @width, @height = Float(width), Float(height)
        @min_width, @min_height, @max_width, @max_height = Float(min_width), Float(min_height), Float(max_width), Float(max_height)
        raise ArgumentError, "resizable bounds are invalid" unless @min_width.positive? && @min_height.positive? && @max_width >= @min_width && @max_height >= @min_height
        @width, @height = @width.clamp(@min_width, @max_width), @height.clamp(@min_height, @max_height)
      end

      def on_resize(&block) = (@on_resize = block; self)

      def build(cx)
        @cx = cx
        handle = Div.new.w(12).h(12).bg(cx.theme.colors.border).cursor(:resize_diagonal)
          .style(position: :absolute, right: 0, bottom: 0)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 1))
          .focusable(context: {in_slider: true}) { |action| adjust(action) }
          .on_drag { |event, context| resize_to(event.position.x - @bounds.x, event.position.y - @bounds.y, context); :capture }
        Div.new.w(@width).h(@height).overflow_hidden.border(1).border_color(cx.theme.colors.border).child(@content).child(handle)
      end

      def tui_cells(*) = "┌#{"─" * 8}┐\n#{text(@content)}\n└#{"─" * 7}┘↘"
      def accessibility_node(cx) = node(:group, states: {resizable: true, width: @width, height: @height},
        children: [@content.accessibility_node(cx), Accessibility.node(role: :separator, label: "Resize", actions: %i[increment decrement])].compact)

      private

      def adjust(action)
        delta = {decrement: -8, decrement_page: -32, increment: 8, increment_page: 32}[action]
        delta && resize_to(@width + delta, @height + delta, @cx)
      end

      def resize_to(width, height, cx)
        next_width, next_height = Float(width).clamp(@min_width, @max_width), Float(height).clamp(@min_height, @max_height)
        return false if [next_width, next_height] == [@width, @height]
        @width, @height = next_width, next_height
        @on_resize&.call(Size.new(@width, @height), cx)
        cx&.window&.request_frame
        true
      end

      def text(value) = value.respond_to?(:tui_cells) ? value.tui_cells : value.respond_to?(:text) ? value.text : "content"
    end

    class DockPanel < Component
      def initialize(center:, top: nil, right: nil, bottom: nil, left: nil)
        super()
        @center, @top, @right, @bottom, @left = center, top, right, bottom, left
      end

      def build(_cx)
        middle = Div.new.flex_row.flex_1
        middle.child(@left) if @left
        middle.child(Div.new.flex_1.child(@center))
        middle.child(@right) if @right
        Div.new.w_full.h_full.tap do |root|
          root.child(@top) if @top
          root.child(middle)
          root.child(@bottom) if @bottom
        end
      end

      def tui_cells(*) = [@top, [@left, @center, @right].compact.map { |item| text(item) }.join(" | "), @bottom].compact.map { |item| item.is_a?(String) ? item : text(item) }.join("\n")
      def accessibility_node(cx) = node(:group, children: [@top, @left, @center, @right, @bottom].filter_map { |item| item.accessibility_node(cx) if item&.respond_to?(:accessibility_node) })

      private

      def text(value) = value.respond_to?(:tui_cells) ? value.tui_cells : value.respond_to?(:text) ? value.text : "panel"
    end

    class ListView < Component
      attr_reader :selected_index, :selected_value

      def initialize(items, height: 320, row_height: 30, selected: nil, &render_item)
        super()
        @items, @height, @row_height, @render_item = Array(items), Float(height), Float(row_height), render_item
        raise ArgumentError, "list dimensions must be positive" unless @height.positive? && @row_height.positive?
        @selected_index = selected.nil? ? nil : Integer(selected)
        raise ArgumentError, "selected list index is outside the items" if @selected_index && !@selected_index.between?(0, @items.length - 1)
      end

      def on_select(&block) = (@on_select = block; self)

      def build(cx)
        @cx = cx
        @list = List.new(count: @items.length, estimated_height: @row_height) { |index| row(index, cx) }.h(@height)
        @list.focusable(context: {in_list: true}) { |action| list_action(action) }
      end

      def tui_cells(*) = @items.first(20).map.with_index { |item, index| "#{index == @selected_index ? ">" : " "} #{label(item)}" }.join("\n")
      def accessibility_node(_cx) = node(:list, value: selected_value, children: @items.map.with_index { |item, index|
        Accessibility.node(role: :listitem, label: label(item), states: {selected: index == @selected_index}, actions: [:select])
      })

      def selected_value = @selected_index && @items[@selected_index]

      private

      def row(index, cx)
        item = @items[index]
        content = @render_item ? @render_item.call(item, index) : Label.new(label(item), size: :sm)
        Div.new.key(index).h(@row_height).p([4, 8]).items_center.cursor(:pointer)
          .bg(index == @selected_index ? cx.theme.colors.selection : "#0000")
          .on_click { |event, context| select(index, event, context) }.child(content)
      end

      def label(item) = item.respond_to?(:label) ? item.label.to_s : item.to_s

      def list_action(action)
        return false if @items.empty?
        index = case action
        when :previous_option then [(@selected_index || 0) - 1, 0].max
        when :next_option then [(@selected_index || -1) + 1, @items.length - 1].min
        when :first then 0
        when :last then @items.length - 1
        when :page_up then [(@selected_index || 0) - visible_count, 0].max
        when :page_down then [(@selected_index || 0) + visible_count, @items.length - 1].min
        when :activate then @selected_index || 0
        else return false
        end
        select(index, nil, @cx)
      end

      def visible_count = [(@height / @row_height).floor, 1].max

      def select(index, event, cx)
        @selected_index = index
        @list.scroll_to(index, align: :nearest)
        @on_select&.call(@items[index], index, event, cx)
        cx&.window&.request_frame
        true
      end
    end
  end
end
