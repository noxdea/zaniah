# frozen_string_literal: true

module Zaniah
  module Layout
    class Engine
      include GridLayout
      EDGE_KEYS = {
        padding: [%i[padding_top padding_right padding_bottom padding_left], :padding_start, :padding_end],
        margin: [%i[margin_top margin_right margin_bottom margin_left], :margin_start, :margin_end],
        border: [%i[border_top border_right border_bottom border_left], :border_start, :border_end]
      }.freeze
      ZERO_EDGES = [0, 0, 0, 0].freeze

      def initialize(rem: 16) = @rem = rem

      def compute(root, width:, height:, x: 0, y: 0)
        layout(root, x, y, width, height, width, height)
        root.bounds
      end
      def measure(node, width:, height:) = natural_size(node, width, height)

      private

      def resolve_length(length, available, fallback = nil)
        return fallback if length.nil? || length == :auto
        return length.resolve(available || 0, rem: @rem) if length.is_a?(Length)
        length.is_a?(Numeric) ? length : Float(length)
      end

      def resolve_edges(style, name, available)
        values = style.to_h
        input = values[name]
        direction = values[:direction]
        raise ArgumentError, "direction must be ltr or rtl" unless %i[ltr rtl].include?(direction)
        physical, start_key, end_key = EDGE_KEYS.fetch(name)
        sides = physical.map { |key| values[key] }
        start, finish = values[start_key], values[end_key]
        if input.is_a?(Numeric) && sides.none? && start.nil? && finish.nil?
          return ZERO_EDGES if input.zero?
          return [input, input, input, input]
        end

        input = input.to_h.values if input.is_a?(Edges)
        input = [input] unless input.is_a?(Array)
        input = case input.length
        when 1 then input * 4
        when 2 then [input[0], input[1], input[0], input[1]]
        when 3 then [input[0], input[1], input[2], input[1]]
        when 4 then input
        else raise ArgumentError, "invalid #{name}"
        end
        values = sides.each_with_index.map do |value, i|
          val = value || input[i]
          val == :auto ? :auto : resolve_length(val, available, 0)
        end
        left, right = direction == :ltr ? [start, finish] : [finish, start]
        values[3] = left == :auto ? :auto : resolve_length(left, available, 0) unless left.nil?
        values[1] = right == :auto ? :auto : resolve_length(right, available, 0) unless right.nil?
        values
      end

      def clamp_size(node, dimension, size, available)
        clamp_value(node.style.to_h, dimension, size, available)
      end

      def clamp_value(values, dimension, size, available)
        if dimension == :width
          min, max = values[:min_width], values[:max_width]
        else
          min, max = values[:min_height], values[:max_height]
        end
        return size.clamp(min, [min, max].max) if min.is_a?(Numeric) && max.is_a?(Numeric)
        min = resolve_length(min, available, 0)
        max = resolve_length(max, available, Float::INFINITY)
        size.clamp(min, [min, max].max)
      end

      def natural_size(node, available_w, available_h)
        style = node.style
        s = style.to_h
        return [0, 0] if s[:display] == :none
        if !node.measure && node.children.empty? && s.length == Style::DEFAULTS.length &&
            s[:padding] == 0 && s[:border] == 0 && !s[:aspect_ratio] &&
            !s[:padding_start] && !s[:padding_end] && !s[:border_start] && !s[:border_end] &&
            s[:min_width] == 0 && s[:min_height] == 0 &&
            s[:max_width] == Float::INFINITY && s[:max_height] == Float::INFINITY
          return [resolve_length(s[:width], available_w, 0), resolve_length(s[:height], available_h, 0)]
        end
        padding, border = uniform_edge(style, :padding), uniform_edge(style, :border)
        if padding && border
          padding_w = padding_h = (padding + border) * 2
        else
          p = resolve_edges(style, :padding, available_w).map { |edge| edge == :auto ? 0 : edge }
          b = resolve_edges(style, :border, available_w).map { |edge| edge == :auto ? 0 : edge }
          padding_w, padding_h = p[1] + p[3] + b[1] + b[3], p[0] + p[2] + b[0] + b[2]
        end
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
        [clamp_value(s, :width, w || padding_w, available_w), clamp_value(s, :height, h || padding_h, available_h)]
      end

      def uniform_edge(style, name)
        values = style.to_h
        physical, start_key, end_key = EDGE_KEYS.fetch(name)
        value = values[name]
        value if value.is_a?(Numeric) && physical.none? { |key| values[key] } && values[start_key].nil? && values[end_key].nil?
      end

      def layout(node, x, y, width, height, available_w, available_h, clamp = true)
        if node.children.empty?
          if node.style[:display] == :none
            node.bounds = Bounds.new(x, y, 0, 0)
          else
            width = clamp_size(node, :width, width, available_w) if clamp
            height = clamp_size(node, :height, height, available_h) if clamp
            node.bounds = Bounds.new(x, y, width, height)
          end
          return
        end
        key = [node.generation, x, y, width, height, available_w, available_h]
        return if node.cache[key]
        if node.style[:display] == :none
          node.bounds = Bounds.new(x, y, 0, 0)
          node.children.each { |child| hide(child, x, y) }
          return
        end
        if clamp
          width = clamp_size(node, :width, width, available_w)
          height = clamp_size(node, :height, height, available_h)
        end
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
        s = node.style.to_h
        row = s[:flex_direction].to_s.start_with?("row")
        reverse = s[:flex_direction].to_s.end_with?("reverse")
        main_size, cross_size = row ? [content.width, content.height] : [content.height, content.width]
        before, after, cross_before, cross_after = row ? [3, 1, 0, 2] : [0, 2, 3, 1]
        main_dimension, cross_dimension = row ? [:width, :height] : [:height, :width]
        gap = resolve_length(s[:gap], main_size, 0)
        flow = flow.reject { |child| child.style.to_h[:display] == :none && hide(child, node.bounds.x, node.bounds.y) }
        if s[:flex_wrap] == :nowrap && s[:justify_content] == :start && s[:align_items] == :stretch &&
            layout_simple_flow(flow, content, row, reverse, main_size, cross_size, cross_dimension, gap)
          return
        end
        items = flow.map do |child|
          style = child.style.to_h
          nw, nh = natural_size(child, content.width, content.height)
          basis = style[:flex_basis]
          base = resolve_length(basis, main_size, row ? nw : nh)
          margins = resolve_edges(child.style, :margin, content.width)
          size = basis == :auto ? base : clamp_size(child, main_dimension, base, main_size)
          {node: child, base: base, size: size,
           cross: row ? nh : nw, margins: margins, style: style}
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
          fixed_margin = line.sum do |item|
            margins = item[:margins]
            (margins[before] == :auto ? 0 : margins[before]) + (margins[after] == :auto ? 0 : margins[after])
          end
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
          baseline = line.reduce(0) { |value, item| item[:node].baseline > value ? item[:node].baseline : value }
          cursor = leading
          line.each do |item|
            child, margins = item[:node], item[:margins]
            mb = margins[before] == :auto ? auto_margin : margins[before]
            ma = margins[after] == :auto ? auto_margin : margins[after]
            cb = margins[cross_before] == :auto ? 0 : margins[cross_before]
            ca = margins[cross_after] == :auto ? 0 : margins[cross_after]
            style = item[:style]
            align = style[:align_self] == :auto ? s[:align_items] : style[:align_self]
            cross = item[:cross]
            cross = [line_cross - cb - ca, 0].max if align == :stretch && style[cross_dimension] == :auto
            default_limits = cross_dimension == :width ? style[:min_width] == 0 && style[:max_width] == Float::INFINITY : style[:min_height] == 0 && style[:max_height] == Float::INFINITY
            cross = clamp_size(child, cross_dimension, cross, cross_size) unless default_limits
            cross_free = line_cross - cross - cb - ca
            cross_offset = case align
            when :end then cross_free
            when :center then cross_free / 2.0
            when :baseline then baseline - child.baseline
            else 0
            end
            cross_autos = (margins[cross_before] == :auto ? 1 : 0) + (margins[cross_after] == :auto ? 1 : 0)
            if cross_autos.positive?
              cross_offset = margins[cross_before] == :auto ? [cross_free, 0].max / cross_autos : 0
            end
            cursor += mb
            main_position = reverse ? main_size - cursor - item[:size] : cursor
            cross_position = cross_cursor + cb + cross_offset
            if row
              cx, cy, cw, ch = content.x + main_position, content.y + cross_position, item[:size], cross
            else
              cx, cy, cw, ch = content.x + cross_position, content.y + main_position, cross, item[:size]
            end
            if style[:left] || style[:right]
              cx += resolve_length(style[:left], content.width, 0) - resolve_length(style[:right], content.width, 0)
            end
            if style[:top] || style[:bottom]
              cy += resolve_length(style[:top], content.height, 0) - resolve_length(style[:bottom], content.height, 0)
            end
            layout(child, cx, cy, cw, ch, content.width, content.height, false)
            cursor += item[:size] + ma + spacing
          end
          cross_cursor += line_cross + gap
        end
      end

      def layout_simple_flow(flow, content, row, reverse, main_size, cross_size, cross_dimension, gap)
        styles = flow.map { |child| child.style.to_h }
        return false unless styles.all? do |style|
          margin = style[:margin]
          margin.is_a?(Numeric) && margin.zero? && style[:position] == :relative && style[:flex_basis] == :auto &&
            (style[:align_self] == :auto || style[:align_self] == :stretch) && style[:min_width] == 0 && style[:min_height] == 0 &&
            style[:max_width] == Float::INFINITY && style[:max_height] == Float::INFINITY &&
            style[:margin_top].nil? && style[:margin_right].nil? && style[:margin_bottom].nil? && style[:margin_left].nil? &&
            style[:margin_start].nil? && style[:margin_end].nil? && style[:left].nil? && style[:right].nil? &&
            style[:top].nil? && style[:bottom].nil? && style[:flex_grow].is_a?(Numeric) && style[:flex_shrink].is_a?(Numeric)
        end

        bases, crosses = flow.map do |child|
          width, height = natural_size(child, content.width, content.height)
          row ? [width, height] : [height, width]
        end.transpose
        bases ||= []
        crosses ||= []
        available = main_size - gap * [flow.length - 1, 0].max
        total = bases.sum
        growing = total < available
        factor = styles.each_with_index.sum do |style, index|
          growing ? style[:flex_grow] : style[:flex_shrink] * bases[index]
        end
        free = available - total
        divisor = growing ? [factor, 1].max : factor
        sizes = bases.each_index.map do |index|
          weight = growing ? styles[index][:flex_grow] : styles[index][:flex_shrink] * bases[index]
          bases[index] + (factor.positive? ? free * weight / divisor : 0)
        end
        return false if sizes.any?(&:negative?)

        cursor = 0
        flow.each_with_index do |child, index|
          style = styles[index]
          size = sizes[index]
          cross = style[cross_dimension] == :auto ? cross_size : crosses[index]
          main_position = reverse ? main_size - cursor - size : cursor
          if row
            layout(child, content.x + main_position, content.y, size, cross, content.width, content.height, false)
          else
            layout(child, content.x, content.y + main_position, cross, size, content.width, content.height, false)
          end
          cursor += size + gap
        end
        true
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
          factor = active.sum { |i| growing ? i[:style][:flex_grow] : i[:style][:flex_shrink] * i[:base] }
          free = remaining - active.sum { |i| i[:base] }
          frozen = []
          active.each do |item|
            weight = growing ? item[:style][:flex_grow] : item[:style][:flex_shrink] * item[:base]
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
