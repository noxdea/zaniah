# frozen_string_literal: true

module Zaniah
  module UI
    class DockWorkspace < Component
      attr_reader :layout

      def initialize(layout, render:)
        super()
        @layout = layout.is_a?(DockLayout) ? layout : DockLayout.from_h(layout)
        raise ArgumentError, "dock renderer must be callable" unless render.respond_to?(:call)
        @render = render
      end

      def on_layout_change(&block) = (@on_layout_change = block; self)
      def on_detach(&block) = (@on_detach = block; self)

      def build(cx)
        @cx, @groups, @splits, @rendered = cx, {}, {}, {}
        build_node(@layout.root, cx)
      end

      def prepaint(bounds, state, cx)
        super
        @group_boxes = @groups.transform_values { |element| element.layout_node.bounds }
      end

      def select(panel_id)
        panel_id = panel_id.to_s
        group = @layout.find_panel(panel_id)
        return false unless group && group.active != panel_id
        tree = @layout.to_h
        node = find_node(tree, group.id)
        node["active"] = panel_id
        replace_layout(tree)
      end

      def move(panel_id, to:, index: nil)
        panel_id, target_id = panel_id.to_s, to.to_s
        source = @layout.find_panel(panel_id)
        return false unless source && @layout.find_group(target_id)
        tree = @layout.to_h
        source_node, target_node = find_node(tree, source.id), find_node(tree, target_id)
        source_node["panels"].delete(panel_id)
        source_node["active"] = source_node["panels"].first if source_node["active"] == panel_id
        target_node["panels"].insert(index.nil? ? target_node["panels"].length : Integer(index).clamp(0, target_node["panels"].length), panel_id)
        target_node["active"] = panel_id
        replace_layout(prune(tree))
      end

      def split(panel_id, target:, side:)
        panel_id, target_id = panel_id.to_s, target.to_s
        raise ArgumentError, "dock side must be left, right, top, or bottom" unless %i[left right top bottom].include?(side)
        source = @layout.find_panel(panel_id)
        target_group = @layout.find_group(target_id)
        return false unless source && target_group
        return false if source.id == target_id && source.panels.length == 1

        tree = @layout.to_h
        source_node = find_node(tree, source.id)
        source_node["panels"].delete(panel_id)
        source_node["active"] = source_node["panels"].first if source_node["active"] == panel_id
        fresh_group = {"type" => "tabs", "id" => unique_id(tree, "#{target_id}-tabs"),
          "panels" => [panel_id], "active" => panel_id}
        target_node = find_node(tree, target_id)
        first, second = %i[left top].include?(side) ? [fresh_group, target_node] : [target_node, fresh_group]
        split_node = {"type" => "split", "id" => unique_id(tree, "#{target_id}-split"),
          "orientation" => %i[left right].include?(side) ? "horizontal" : "vertical",
          "ratio" => 0.5, "first" => first, "second" => second}
        tree = replace_node(tree, target_id, split_node)
        replace_layout(prune(tree))
      end

      def detach(panel_id)
        panel_id = panel_id.to_s
        return false unless @on_detach && @layout.find_panel(panel_id)
        @on_detach.call(panel_id)
        true
      end

      def tui_cells(*) = tui_node(@layout.root)

      def accessibility_node(cx) = node(:group, children: [semantic_node(@layout.root, cx)])

      def accessibility_action(item, action)
        if (panel_id = item.states[:panel_id])
          return select(panel_id) if action == :select
          return detach(panel_id) if action == :detach
        end
        if (split_id = item.states[:split_id])
          return resize_split(split_id, action == :increment ? 0.02 : -0.02) if %i[increment decrement].include?(action)
        end
        false
      end

      private

      def build_node(node, cx)
        return build_group(node, cx) if node.is_a?(DockLayout::Tabs)
        first, second = build_node(node.first, cx), build_node(node.second, cx)
        pane = SplitPane.new(first, second, orientation: node.orientation, ratio: node.ratio)
          .on_change { |ratio, _context| set_ratio(node.id, ratio) }
        @splits[node.id] = pane
        pane
      end

      def build_group(group, cx)
        header = Div.new.flex_row.items_center.h(42).bg(cx.theme.colors.surface)
          .border_b(1).border_color(cx.theme.colors.border)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
          .focusable(context: {in_dock: true}) { |action| dock_action(group.id, action) }
        group.panels.each do |panel_id|
          selected = panel_id == group.active
          header.child(Div.new.h(40).p([6, 12]).items_center.cursor(:pointer)
            .bg(selected ? cx.theme.colors.surface_hover : "#0000")
            .border_b(selected ? 2 : 0).border_color(cx.theme.colors.accent)
            .on_mouse_down { |event, _context| tab_down(panel_id, event) }
            .on_drag { |event, _context| tab_drag(event) }
            .on_mouse_up { |event, _context| tab_up(event) }
            .child(Text.new(panel_id.encode(Encoding::UTF_8), color: cx.theme.colors.text)))
        end
        content = @render.call(group.active)
        raise TypeError, "dock renderer must return a renderable element" unless content.respond_to?(:request_layout)
        @rendered[group.id] = content
        root = Div.new.key(group.id).w_full.h_full.overflow_hidden
          .border(1).border_color(cx.theme.colors.border)
          .child(header).child(Div.new.flex_1.overflow_hidden.child(content))
        @groups[group.id] = root
      end

      def tab_down(panel_id, event)
        select(panel_id)
        @drag = {panel_id: panel_id, start: event.position, moved: false}
        true
      end

      def tab_drag(event)
        return false unless @drag
        start = @drag[:start]
        @drag[:moved] ||= (event.position.x - start.x).abs + (event.position.y - start.y).abs >= 6
        :capture
      end

      def tab_up(event)
        drag, @drag = @drag, nil
        return false unless drag
        drop(drag[:panel_id], event.position) if drag[:moved]
        true
      end

      def drop(panel_id, point)
        target_id, box = @group_boxes&.find { |_id, bounds| bounds.contains?(point) }
        return detach(panel_id) unless target_id
        edge = [[:left, point.x - box.x], [:right, box.right - point.x],
          [:top, point.y - box.y], [:bottom, box.bottom - point.y]].min_by(&:last)
        limit = %i[left right].include?(edge.first) ? box.width * 0.2 : box.height * 0.2
        edge.last < limit ? split(panel_id, target: target_id, side: edge.first) : move(panel_id, to: target_id)
      end

      def dock_action(group_id, action)
        group = @layout.find_group(group_id)
        return false unless group
        index = group.panels.index(group.active)
        case action
        when :previous_option then select(group.panels[(index - 1) % group.panels.length])
        when :next_option then select(group.panels[(index + 1) % group.panels.length])
        when :first then select(group.panels.first)
        when :last then select(group.panels.last)
        when :move_previous, :move_next
          step = action == :move_previous ? -1 : 1
          target = @layout.groups[(@layout.groups.index(group) + step) % @layout.groups.length]
          target.id == group_id ? move(group.active, to: group_id, index: (index + step).clamp(0, group.panels.length - 1)) : move(group.active, to: target.id)
        when :split_left, :split_right, :split_top, :split_bottom
          split(group.active, target: group.id, side: action.to_s.delete_prefix("split_").to_sym)
        when :detach then detach(group.active)
        else false
        end
      end

      def set_ratio(id, ratio)
        tree = @layout.to_h
        find_node(tree, id)["ratio"] = ratio
        replace_layout(tree)
      end

      def resize_split(id, delta)
        tree = @layout.to_h
        split = find_node(tree, id)
        return false unless split && split["type"] == "split"
        split["ratio"] = (split["ratio"] + delta).clamp(0.1, 0.9)
        replace_layout(tree)
      end

      def replace_layout(tree)
        next_layout = DockLayout.from_h(tree)
        return false if next_layout.to_h == @layout.to_h
        old, @layout = @layout, next_layout
        @on_layout_change&.call(next_layout)
        @cx&.window&.request_frame
        true
      rescue StandardError
        @layout = old if old
        raise
      end

      def find_node(tree, id)
        return tree if tree["id"] == id
        return nil unless tree["type"] == "split"
        find_node(tree["first"], id) || find_node(tree["second"], id)
      end

      def replace_node(tree, id, replacement)
        return replacement if tree["id"] == id
        return tree unless tree["type"] == "split"
        tree["first"] = replace_node(tree["first"], id, replacement)
        tree["second"] = replace_node(tree["second"], id, replacement)
        tree
      end

      def prune(tree)
        return tree unless tree["type"] == "split"
        tree["first"], tree["second"] = prune(tree["first"]), prune(tree["second"])
        return tree["second"] if tree["first"]["type"] == "tabs" && tree["first"]["panels"].empty?
        return tree["first"] if tree["second"]["type"] == "tabs" && tree["second"]["panels"].empty?
        tree
      end

      def unique_id(tree, stem)
        ids = []
        visit = ->(node) do
          ids << node["id"]
          if node["type"] == "split"
            visit.call(node["first"])
            visit.call(node["second"])
          end
        end
        visit.call(tree)
        candidate = stem
        number = 2
        while ids.include?(candidate)
          candidate = "#{stem}-#{number}"
          number += 1
        end
        candidate
      end

      def tui_node(node)
        return "[#{node.panels.map { |panel| panel == node.active ? "(#{panel})" : panel }.join('|')}]" if node.is_a?(DockLayout::Tabs)
        [tui_node(node.first), tui_node(node.second)].join(node.orientation == :horizontal ? " │ " : "\n───\n")
      end

      def semantic_node(node, cx)
        if node.is_a?(DockLayout::Tabs)
          tabs = node.panels.map do |panel|
            Accessibility.node(role: :tab, id: [:dock_tab, panel].freeze, label: panel,
              states: {selected: panel == node.active, panel_id: panel}, actions: %i[select detach])
          end
          panel = @rendered&.[](node.id) || @render.call(node.active)
          content = panel.accessibility_node(cx) if panel.respond_to?(:accessibility_node)
          return Accessibility.node(role: :group, id: [:dock_group, node.id].freeze,
            children: [Accessibility.node(role: :tablist, children: tabs),
              Accessibility.node(role: :tabpanel, label: node.active, children: [content].compact)])
        end
        separator = Accessibility.node(role: :separator, id: [:dock_divider, node.id].freeze,
          value: node.ratio, states: {split_id: node.id, orientation: node.orientation}, actions: %i[increment decrement])
        Accessibility.node(role: :group, id: [:dock_split, node.id].freeze,
          children: [semantic_node(node.first, cx), separator, semantic_node(node.second, cx)])
      end
    end
  end
end
