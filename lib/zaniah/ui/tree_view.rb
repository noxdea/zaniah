# frozen_string_literal: true

module Zaniah
  module UI
    class TreeView < Component
      Item = Data.define(:id, :label, :value, :children, :loader, :parent, :depth)
      Segment = Data.define(:items, :first, :length, :parent, :depth, :path)
      Location = Data.define(:items, :index, :parent, :depth, :path)

      attr_reader :selected_id, :expanded

      def initialize(items, height: 320, row_height: 28, selected: nil)
        super()
        @source, @height, @row_height = items.to_a, Float(height), Float(row_height)
        raise ArgumentError, "tree dimensions must be positive" unless @height.positive? && @row_height.positive?

        @selected_id, @expanded, @loaded, @locations = selected, Set.new, {}, {}
        reset_index
      end

      def on_select(&block) = (@on_select = block; self)
      def on_toggle(&block) = (@on_toggle = block; self)
      def expand(id) = (toggle(id, true); self)
      def collapse(id) = (toggle(id, false); self)

      def replace(items)
        wanted = @expanded.dup
        @source, @locations = items.to_a, {}
        @expanded.clear
        reset_index
        restore_expansions(wanted)
        @selected_id = nil if !@selected_id.nil? && !visible_index(@selected_id)
        @cx&.window&.request_frame
        self
      end

      def build(cx)
        @cx = cx
        rebuild_segments if @indexed_expanded != @expanded
        unless @list&.heights&.count == @visible_count
          scroll = @list&.scroll_y || 0
          @list = List.new(count: @visible_count, estimated_height: @row_height) do |index|
            row(visible_item(index), index, @cx)
          end
          @list.scroll_y = scroll
        end
        @list.h(@height)
        @list.focusable(context: {in_tree: true}) { |action| tree_action(action) }
      end

      def tui_cells(*)
        (0...[@visible_count, 20].min).map do |index|
          item = visible_item(index)
          "#{"  " * item.depth}#{branch(item)} #{item.label}"
        end.join("\n")
      end

      def accessibility_node(_cx)
        range = @list.visible_range if @list&.heights&.count == @visible_count
        range = 0...[@visible_count, (@height / @row_height).ceil + 2].min if !range || range.size.zero?
        focused = @cx&.dispatcher&.focused.equal?(@list&.focus_handle)
        children = range.map.with_index do |index, visible_index|
          item = visible_item(index)
          expandable = expandable?(item)
          location = @locations.fetch(item.id)
          actions = [:select]
          actions << (@expanded.include?(item.id) ? :collapse : :expand) if expandable
          Accessibility.node(role: :treeitem, id: item.id, label: item.label,
            bounds: @list&.children&.[](visible_index)&.layout_node&.bounds,
            states: {level: item.depth + 1, position: location.index + 1, size: location.items.length,
              item_id: item.id, selected: item.id == @selected_id,
              focused: focused && item.id == @selected_id,
              expanded: expandable ? @expanded.include?(item.id) : nil}, actions: actions)
        end
        node(:tree, states: {size: @visible_count}, children: children)
      end

      def accessibility_action(node, action)
        id = node.states[:item_id]
        return if id.nil?
        index = visible_index(id)
        return false unless index
        item = visible_item(index)
        case action
        when :select
          @cx&.dispatcher&.focus(@list.focus_handle, origin: :programmatic)
          select(item, index, nil, @cx)
        when :expand then toggle(id, true)
        when :collapse then toggle(id, false)
        else nil
        end
      end

      private

      def reset_index
        @segments, @visible_count = [], 0
        append_segment(@source, 0, @source.length, nil, 0, [].freeze)
        @indexed_expanded = @expanded.dup
      end

      def rebuild_segments
        groups = Hash.new { |hash, key| hash[key] = [] }
        @expanded.each do |id|
          location = @locations[id]
          groups[[location.items.object_id, location.parent]] << location if location_valid?(id, location)
        end
        @segments, @visible_count = [], 0
        append_collection(@source, nil, 0, [].freeze, groups)
        @indexed_expanded = @expanded.dup
      end

      def append_collection(items, parent, depth, path, groups)
        cursor = 0
        locations = groups.fetch([items.object_id, parent], []).sort_by(&:index)
        locations.each do |location|
          next unless location.index.between?(cursor, items.length - 1)

          append_segment(items, cursor, location.index - cursor + 1, parent, depth, path)
          item = normalize_item(items[location.index], parent, depth, path + [location.index], items)
          children = children_for(item)
          append_collection(children, item.id, depth + 1, item_path(item), groups) unless children.empty?
          cursor = location.index + 1
        end
        append_segment(items, cursor, items.length - cursor, parent, depth, path)
      end

      def append_segment(items, first, length, parent, depth, path)
        return unless length.positive?

        @segments << Segment.new(items: items, first: first, length: length,
          parent: parent, depth: depth, path: path)
        @visible_count += length
      end

      def visible_item(index)
        raise IndexError, "tree row outside visible items" unless index.is_a?(Integer) && index.between?(0, @visible_count - 1)

        offset = index
        @segments.each do |segment|
          if offset < segment.length
            source_index = segment.first + offset
            return normalize_item(segment.items[source_index], segment.parent, segment.depth,
              segment.path + [source_index], segment.items)
          end
          offset -= segment.length
        end
      end

      def normalize_item(source, parent, depth, path, items)
        path = path.freeze
        if source.is_a?(Hash)
          children = source[:children]
          loader = children.respond_to?(:call) ? children : source[:load]
          item = Item.new(id: source.fetch(:id, path), label: source.fetch(:label, source[:value]).to_s,
            value: source.fetch(:value, source), children: loader.equal?(children) ? [] : Array(children),
            loader: loader, parent: parent, depth: depth)
        elsif source.is_a?(Array) && source.length == 2 && source.last.is_a?(Array)
          item = Item.new(id: path, label: source.first.to_s, value: source.first,
            children: source.last, loader: nil, parent: parent, depth: depth)
        else
          children = source.children if source.respond_to?(:children)
          loader = children if children.respond_to?(:call)
          item = Item.new(id: source.respond_to?(:id) ? source.id : path,
            label: source.respond_to?(:label) ? source.label.to_s : source.to_s,
            value: source, children: loader ? [] : Array(children), loader: loader,
            parent: parent, depth: depth)
        end
        raise ArgumentError, "tree item id must not be nil" if item.id.nil?
        raise TypeError, "tree item loader must respond to call" if item.loader && !item.loader.respond_to?(:call)

        remember(item, Location.new(items: items, index: path.last,
          parent: parent, depth: depth, path: path))
      end

      def remember(item, location)
        existing = @locations[item.id]
        if existing && !(existing.items.equal?(location.items) && existing.index == location.index && existing.parent == location.parent)
          raise ArgumentError, "duplicate tree item id #{item.id.inspect}"
        end
        @locations[item.id] = location
        item
      end

      def source_id(source, path)
        id = if source.is_a?(Hash)
          source.fetch(:id, path)
        elsif source.is_a?(Array) && source.length == 2 && source.last.is_a?(Array)
          path
        else
          source.respond_to?(:id) ? source.id : path
        end
        raise ArgumentError, "tree item id must not be nil" if id.nil?

        id
      end

      def children_for(item) = @loaded.fetch(item.id, item.children)
      def expandable?(item) = !!(item.loader || !children_for(item).empty?)
      def branch(item) = expandable?(item) ? (@expanded.include?(item.id) ? "▾" : "▸") : " "
      def item_path(item) = @locations.fetch(item.id).path

      def location_valid?(id, location)
        location && location.index.between?(0, location.items.length - 1) &&
          source_id(location.items[location.index], location.path) == id
      end

      def visible_index(id)
        location = @locations[id]
        if location_valid?(id, location)
          index = index_for_location(location)
          return index if index
        end
        offset = 0
        @segments.each do |segment|
          segment.length.times do |index|
            source_index = segment.first + index
            path = (segment.path + [source_index]).freeze
            next unless source_id(segment.items[source_index], path) == id

            @locations[id] = Location.new(items: segment.items, index: source_index,
              parent: segment.parent, depth: segment.depth, path: path)
            return offset + index
          end
          offset += segment.length
        end
        nil
      end

      def index_for_location(location)
        offset = 0
        @segments.each do |segment|
          if segment.items.equal?(location.items) && segment.parent == location.parent &&
              location.index.between?(segment.first, segment.first + segment.length - 1)
            return offset + location.index - segment.first
          end
          offset += segment.length
        end
        nil
      end

      def find_item(id)
        index = visible_index(id)
        index && visible_item(index)
      end

      def toggle(id, value = nil)
        item = find_item(id)
        return false unless item && expandable?(item)

        open = value.nil? ? !@expanded.include?(id) : !!value
        return false if open == @expanded.include?(id)
        @loaded[id] = Array(item.loader.call(item.value)) if open && item.loader && !@loaded.key?(id)
        open ? @expanded.add(id) : @expanded.delete(id)
        rebuild_segments
        select_parent_after_collapse(item) unless open
        @cx&.window&.request_frame
        @on_toggle&.call(id, open)
        true
      end

      def select_parent_after_collapse(item)
        selected = @locations[@selected_id]
        parent = @locations[item.id]
        return unless selected && parent && selected.path.length > parent.path.length
        return unless selected.path.first(parent.path.length) == parent.path

        @selected_id = item.id
      end

      def restore_expansions(wanted)
        pending = wanted.dup
        loop do
          found = pending.filter_map do |id|
            index = visible_index(id)
            [id, visible_item(index)] if index
          end
          break if found.empty?

          found.each do |id, item|
            pending.delete(id)
            @expanded.add(id) if item.loader ? @loaded.key?(id) : !item.children.empty?
          end
          rebuild_segments
        end
      end

      def row(item, index, cx)
        Div.new.key(item.id).h(@row_height).flex_row.items_center.gap(4).p([2, 6])
          .bg(item.id == @selected_id ? cx.theme.colors.selection : "#0000").cursor(:pointer)
          .on_click { |event, context| select(item, index, event, context) }
          .children(Array.new(item.depth) { Div.new.w(16).h_full.style(border_widths: Edges.new(0, 1, 0, 0), border_color: cx.theme.colors.border) })
          .child(Button.new(branch(item), size: :sm, variant: :ghost).on_click { toggle(item.id) })
          .child(Label.new(item.label, size: :sm))
      end

      def select(item, index, event, cx)
        @selected_id, @selected_index = item.id, index
        @list&.scroll_to(index, align: :nearest)
        @on_select&.call(item.value, event, cx)
        cx&.window&.request_frame
        true
      end

      def tree_action(action)
        return false if @visible_count.zero?

        index = (!@selected_id.nil? && visible_index(@selected_id)) || @selected_index || 0
        index = index.clamp(0, @visible_count - 1)
        item = visible_item(index)
        case action
        when :previous_option then index = [index - 1, 0].max
        when :next_option then index = [index + 1, @visible_count - 1].min
        when :first then index = 0
        when :last then index = @visible_count - 1
        when :expand
          if @expanded.include?(item.id)
            child = visible_item(index + 1) if index + 1 < @visible_count
            return child&.depth == item.depth + 1 ? select(child, index + 1, nil, @cx) : false
          end
          @selected_id = item.id if @selected_id.nil?
          return toggle(item.id, true)
        when :collapse
          return toggle(item.id, false) if @expanded.include?(item.id)
          parent_index = visible_index(item.parent) if item.parent
          return parent_index ? select(visible_item(parent_index), parent_index, nil, @cx) : false
        else return false
        end
        select(visible_item(index), index, nil, @cx)
      end
    end
  end
end
