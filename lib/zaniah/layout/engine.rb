# frozen_string_literal: true

module Zaniah
  module Layout
    class Engine
      include GridLayout

      def initialize(rem: 16) = @rem = rem

      def compute(root, width:, height:, x: 0, y: 0)
        layout(root, x, y, width, height, width, height)
        root.bounds
      end
      def measure(node, width:, height:) = natural_size(node, width, height)

      private

      def resolve_length(length, available, fallback = nil)
        return fallback if length.nil? || length == :auto
        length.is_a?(Length) ? length.resolve(available || 0, rem: @rem) : Float(length)
      end

      def resolve_edges(style, name, available)
        input = style[name]
        input = input.to_h.values if input.is_a?(Edges)
        input = [input] unless input.is_a?(Array)
        input = case input.length
        when 1 then input * 4
        when 2 then [input[0], input[1], input[0], input[1]]
        when 3 then [input[0], input[1], input[2], input[1]]
        when 4 then input
        else raise ArgumentError, "invalid #{name}"
        end
        values = %i[top right bottom left].each_with_index.map do |side, i|
          val = style["#{name}_#{side}".to_sym] || input[i]
          val == :auto ? :auto : resolve_length(val, available, 0)
        end
        direction = style[:direction]
        raise ArgumentError, "direction must be ltr or rtl" unless %i[ltr rtl].include?(direction)
        start, finish = style["#{name}_start".to_sym], style["#{name}_end".to_sym]
        left, right = direction == :ltr ? [start, finish] : [finish, start]
        values[3] = left == :auto ? :auto : resolve_length(left, available, 0) unless left.nil?
        values[1] = right == :auto ? :auto : resolve_length(right, available, 0) unless right.nil?
        values
      end

      def clamp_size(node, dimension, size, available)
        min = resolve_length(node.style["min_#{dimension}".to_sym], available, 0)
        max = resolve_length(node.style["max_#{dimension}".to_sym], available, Float::INFINITY)
        size.clamp(min, [min, max].max)
      end

      def natural_size(node, available_w, available_h)
        s = node.style
        return [0, 0] if s[:display] == :none
        p = resolve_edges(s, :padding, available_w).map { |v| v == :auto ? 0 : v }
        b = resolve_edges(s, :border, available_w).map { |v| v == :auto ? 0 : v }
        padding_w, padding_h = p[1] + p[3] + b[1] + b[3], p[0] + p[2] + b[0] + b[2]
        w = resolve_length(s[:width], available_w)
        h = resolve_length(s[:height], available_h)
        if s[:aspect_ratio]
          ratio = Float(s[:aspect_ratio])
          raise ArgumentError, "aspect ratio must be positive and finite" unless ratio.positive? && ratio.finite?
          h = w / ratio if w && !h
          w = h * ratio if h && !w
        end
        if node.measure
          measured = node.measure.call([available_w - padding_w, 0].max, [available_h - padding_h, 0].max)
          w ||= measured[0] + padding_w
          h ||= measured[1] + padding_h
          node.baseline = measured[2] || measured[1]
        elsif !node.children.empty?
          sizes = node.children.reject { |c| c.style[:position] == :absolute || c.style[:display] == :none }.map { |c| natural_size(c, available_w, available_h) }
          row = s[:flex_direction].to_s.start_with?("row")
          gap = resolve_length(s[:gap], available_w, 0) * [sizes.length - 1, 0].max
          w ||= (row ? sizes.sum(&:first) + gap : sizes.map(&:first).max || 0) + padding_w
          h ||= (row ? sizes.map(&:last).max || 0 : sizes.sum(&:last) + gap) + padding_h
        end
        [clamp_size(node, :width, w || padding_w, available_w), clamp_size(node, :height, h || padding_h, available_h)]
      end

      def layout(node, x, y, width, height, available_w, available_h)
        key = [node.generation, x, y, width, height, available_w, available_h]
        return if node.cache[key]
        if node.style[:display] == :none
          node.bounds = Bounds.new(x, y, 0, 0)
          node.children.each { |child| hide(child, x, y) }
          return
        end
        width = clamp_size(node, :width, width, available_w)
        height = clamp_size(node, :height, height, available_h)
        node.bounds = Bounds.new(x, y, width, height)
        content = content_bounds(node)
        flow, absolute = node.children.partition { |child| child.style[:position] != :absolute }
        s = node.style
        s[:display] == :grid ? layout_grid_children(node, content, flow) : layout_flow_children(node, content, flow)
        layout_absolute_children(absolute, content)
        node.cache.shift if node.cache.length >= 5
        node.cache[key] = true
      end

      def content_bounds(node)
        padding = resolve_edges(node.style, :padding, node.bounds.width).map { |v| v == :auto ? 0 : v }
        border = resolve_edges(node.style, :border, node.bounds.width).map { |v| v == :auto ? 0 : v }
        node.bounds.inset(Edges.new(*padding.zip(border).map(&:sum)))
      end

      def layout_flow_children(node, content, flow)
        s = node.style
        row = s[:flex_direction].to_s.start_with?("row")
        reverse = s[:flex_direction].to_s.end_with?("reverse")
        main_size, cross_size = row ? [content.width, content.height] : [content.height, content.width]
        before, after, cross_before, cross_after = row ? [3, 1, 0, 2] : [0, 2, 3, 1]
        main_dimension, cross_dimension = row ? [:width, :height] : [:height, :width]
        gap = resolve_length(s[:gap], main_size, 0)
        flow = flow.reject { |child| child.style[:display] == :none && hide(child, node.bounds.x, node.bounds.y) }
        items = flow.map do |child|
          nw, nh = natural_size(child, content.width, content.height)
          base = resolve_length(child.style[:flex_basis], main_size, row ? nw : nh)
          margins = resolve_edges(child.style, :margin, content.width)
          {node: child, base: base, size: clamp_size(child, main_dimension, base, main_size),
           cross: row ? nh : nw, margins: margins}
        end
        lines = [[]]
        occupied = 0
        items.each do |item|
          margin = item[:margins].values_at(before, after).sum { |v| v == :auto ? 0 : v }
          required = item[:size] + margin
          if s[:flex_wrap] == :wrap && !lines.last.empty? && occupied + gap + required > main_size
            lines << []
            occupied = 0
          end
          occupied += (lines.last.empty? ? 0 : gap) + required
          lines.last << item
        end
        cross_cursor = 0
        lines.each do |line|
          next if line.empty?
          fixed_margin = line.sum { |i| i[:margins].values_at(before, after).sum { |v| v == :auto ? 0 : v } }
          distribute_space(line, main_size - gap * (line.length - 1) - fixed_margin, main_dimension)
          free = main_size - line.sum { |i| i[:size] } - fixed_margin - gap * (line.length - 1)
          autos = line.sum { |i| i[:margins].values_at(before, after).count(:auto) }
          auto_margin = autos.positive? ? [free, 0].max / autos : 0
          free = 0 if autos.positive?
          leading, spacing = case s[:justify_content]
          when :end then [free, gap]
          when :center then [free / 2.0, gap]
          when :space_between then [0, gap + (line.length > 1 ? [free, 0].max / (line.length - 1) : 0)]
          when :space_around then [[free, 0].max / line.length / 2.0, gap + [free, 0].max / line.length]
          when :space_evenly then [[free, 0].max / (line.length + 1), gap + [free, 0].max / (line.length + 1)]
          else [0, gap]
          end
          line_cross = lines.length == 1 ? cross_size : line.map { |i| i[:cross] + i[:margins].values_at(cross_before, cross_after).sum { |v| v == :auto ? 0 : v } }.max
          baseline = line.map { |i| i[:node].baseline }.max || 0
          cursor = leading
          line.each do |item|
            child, margins = item.values_at(:node, :margins)
            mb, ma = margins.values_at(before, after).map { |v| v == :auto ? auto_margin : v }
            cb, ca = margins.values_at(cross_before, cross_after).map { |v| v == :auto ? 0 : v }
            align = child.style[:align_self] == :auto ? s[:align_items] : child.style[:align_self]
            cross = item[:cross]
            cross = [line_cross - cb - ca, 0].max if align == :stretch && child.style[cross_dimension] == :auto
            cross = clamp_size(child, cross_dimension, cross, cross_size)
            cross_free = line_cross - cross - cb - ca
            cross_offset = case align
            when :end then cross_free
            when :center then cross_free / 2.0
            when :baseline then baseline - child.baseline
            else 0
            end
            cross_autos = margins.values_at(cross_before, cross_after).count(:auto)
            if cross_autos.positive?
              cross_offset = margins[cross_before] == :auto ? [cross_free, 0].max / cross_autos : 0
            end
            cursor += mb
            main_position = reverse ? main_size - cursor - item[:size] : cursor
            cross_position = cross_cursor + cb + cross_offset
            cx, cy = row ? [content.x + main_position, content.y + cross_position] : [content.x + cross_position, content.y + main_position]
            cw, ch = row ? [item[:size], cross] : [cross, item[:size]]
            cx += resolve_length(child.style[:left], content.width, 0) - resolve_length(child.style[:right], content.width, 0)
            cy += resolve_length(child.style[:top], content.height, 0) - resolve_length(child.style[:bottom], content.height, 0)
            layout(child, cx, cy, cw, ch, content.width, content.height)
            cursor += item[:size] + ma + spacing
          end
          cross_cursor += line_cross + gap
        end
      end

      def layout_absolute_children(children, content)
        children.each do |child|
          nw, nh = natural_size(child, content.width, content.height)
          cs = child.style
          left, right = resolve_length(cs[:left], content.width), resolve_length(cs[:right], content.width)
          top, bottom = resolve_length(cs[:top], content.height), resolve_length(cs[:bottom], content.height)
          cw = resolve_length(cs[:width], content.width, left && right ? content.width - left - right : nw)
          ch = resolve_length(cs[:height], content.height, top && bottom ? content.height - top - bottom : nh)
          cx = content.x + (left || (right ? content.width - right - cw : 0))
          cy = content.y + (top || (bottom ? content.height - bottom - ch : 0))
          layout(child, cx, cy, cw, ch, content.width, content.height)
        end
      end

      def hide(node, x, y)
        node.bounds = Bounds.new(x, y, 0, 0)
        node.children.each { |child| hide(child, x, y) }
        true
      end

      def distribute_space(line, available, dimension)
        growing = line.sum { |i| i[:base] } < available
        active = line.dup
        remaining = available
        until active.empty?
          factor = active.sum { |i| growing ? i[:node].style[:flex_grow] : i[:node].style[:flex_shrink] * i[:base] }
          free = remaining - active.sum { |i| i[:base] }
          frozen = []
          active.each do |item|
            weight = growing ? item[:node].style[:flex_grow] : item[:node].style[:flex_shrink] * item[:base]
            proposed = item[:base] + (factor.positive? ? free * weight / [factor, growing ? 1 : factor].max : 0)
            item[:size] = clamp_size(item[:node], dimension, proposed, available)
            frozen << item if (item[:size] - proposed).abs > 0.00001 || weight.zero?
          end
          break if frozen.empty?
          frozen.each { |item| remaining -= item[:size]; active.delete(item) }
        end
      end
    end

  end
end
