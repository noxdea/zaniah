# frozen_string_literal: true

module Zaniah
  class SVG
    module Rasterizable
    private

    def contours(outline, tolerance: 0.15)
      result, points, x, y = [], nil, 0.0, 0.0
      outline.to_quadratic(tolerance: tolerance).each do |command, *values|
        case command
        when :move_to
          result << [points, false] if points
          x, y = values
          points = [[x, y]]
        when :line_to
          points ||= [[x, y]]
          x, y = values
          points << [x, y]
        when :quad_to
          points ||= [[x, y]]
          cx, cy, endpoint_x, endpoint_y = values
          flatten_quad(points, x, y, cx, cy, endpoint_x, endpoint_y, tolerance, 0)
          x, y = endpoint_x, endpoint_y
        when :close
          next unless points
          result << [points, true]
          x, y = points.first
          points = nil
        end
      end
      result << [points, false] if points
      result
    end

    def flatten_quad(points, x, y, cx, cy, ex, ey, tolerance, depth)
      raise ArgumentError, "SVG curve is too complex" if points.length > 100_000
      if depth >= 16 || Math.hypot(x - 2 * cx + ex, y - 2 * cy + ey) <= tolerance * 4
        points << [ex, ey]
      else
        ax, ay, bx, by = (x + cx) / 2, (y + cy) / 2, (cx + ex) / 2, (cy + ey) / 2
        mx, my = (ax + bx) / 2, (ay + by) / 2
        flatten_quad(points, x, y, ax, ay, mx, my, tolerance, depth + 1)
        flatten_quad(points, mx, my, bx, by, ex, ey, tolerance, depth + 1)
      end
    end

    def mask(outline, width, height, rule)
      return Alhena::Rasterizer.new(width: width, height: height).fill(outline).coverage if rule == "nonzero"
      raise ArgumentError, "unknown SVG fill rule #{rule}" unless rule == "evenodd"
      # The font rasterizer deliberately uses nonzero winding. Even-odd icons
      # need parity instead: subpixel scanlines pair sorted edge intersections.
      edges = contours(outline).flat_map do |points, _closed|
        next [] if points.length < 2
        (points + [points.first]).each_cons(2).reject { |a, b| a[1] == b[1] }.to_a
      end
      coverage = "\0".b * (width * height)
      height.times do |row|
        sums = Array.new(width, 0.0)
        8.times do |sample|
          y = row + (sample + 0.5) / 8
          intersections = edges.filter_map do |a, b|
            low, high = [a[1], b[1]].minmax
            a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1]) if low <= y && y < high
          end.sort
          intersections.each_slice(2) do |left, right|
            next unless right
            left, right = left.clamp(0, width), right.clamp(0, width)
            next if right <= left
            (left.floor...[right.ceil, width].min).each do |column|
              sums[column] += [right, column + 1].min - [left, column].max
            end
          end
        end
        sums.each_with_index { |amount, column| coverage.setbyte(row * width + column, (amount * 255 / 8).round.clamp(0, 255)) }
      end
      coverage
    end

    def clip_mask(element, matrix, width, height, references, inherited = {"clip-rule" => "nonzero"})
      raise ArgumentError, "SVG clip is too complex" if references.length > 32
      raise ArgumentError, "objectBoundingBox clips are not supported" if element.attributes["clipPathUnits"] == "objectBoundingBox"
      style = properties(element, inherited)
      output = "\0".b * (width * height)
      return output if style["display"] == "none" || style["visibility"] == "hidden"
      matrix = multiply(matrix, transform(element.attributes["transform"]))
      if (outline = @paths[element])
        return mask(outline.transform(matrix), width, height, style.fetch("clip-rule", "nonzero"))
      end
      children = element.elements.to_a
      if element.name == "use"
        href = element.attributes["href"] || element.attributes["xlink:href"]
        raise ArgumentError, "invalid or cyclic clip use" unless href&.start_with?("#") && !references.include?(href)
        children = [@ids.fetch(href.delete_prefix("#")) { raise ArgumentError, "unknown clip use #{href}" }]
        matrix = multiply(matrix, [1, 0, 0, 1, length(element.attributes["x"]), length(element.attributes["y"])])
        references += [href]
      end
      children.each do |child|
        next if %w[title desc metadata defs].include?(child.name)
        layer = clip_mask(child, matrix, width, height, references, style)
        output.bytesize.times do |i|
          a, b = output.getbyte(i), layer.getbyte(i)
          output.setbyte(i, a + b - (a * b / 255.0).round)
        end
      end
      output
    end

    def polygon(outline, points)
      return if points.length < 3
      # All stroke pieces have matching winding so their overlap is a union.
      area = (points + [points.first]).each_cons(2).sum { |a, b| a[0] * b[1] - b[0] * a[1] }
      points = points.reverse if area.negative?
      outline.move_to(*points.first)
      points.drop(1).each { |point| outline.line_to(*point) }
      outline.close
    end

    def disk(outline, center, radius)
      segments = [[(Math::PI * Math.sqrt(radius / 0.075)).ceil, 12].max, 512].min
      polygon(outline, Array.new(segments) do |i|
        angle = i * 2 * Math::PI / segments
        [center[0] + Math.cos(angle) * radius, center[1] + Math.sin(angle) * radius]
      end)
    end

    def stroke(outline, width, style)
      cap, join = style["stroke-linecap"], style["stroke-linejoin"]
      raise ArgumentError, "unknown SVG line cap" unless %w[butt round square].include?(cap)
      raise ArgumentError, "unknown SVG line join" unless %w[miter round bevel].include?(join)
      limit = number(style["stroke-miterlimit"])
      raise ArgumentError, "SVG miter limit must be at least one" if limit < 1
      radius, result = width / 2.0, Alhena::Outline.new
      contours(outline).each do |points, closed|
        points = points.each_with_object([]) { |point, unique| unique << point if unique.last != point }
        points.pop if closed && points.length > 1 && points.first == points.last
        if points.length == 1
          disk(result, points.first, radius) if cap == "round"
          if cap == "square"
            x, y = points.first
            polygon(result, [[x - radius, y - radius], [x + radius, y - radius], [x + radius, y + radius], [x - radius, y + radius]])
          end
          next
        end
        segments = (closed ? points + [points.first] : points).each_cons(2).map do |a, b|
          dx, dy = b[0] - a[0], b[1] - a[1]
          length = Math.hypot(dx, dy)
          [a, b, dx / length, dy / length]
        end
        segments.each_with_index do |(a, b, dx, dy), index|
          nx, ny = -dy * radius, dx * radius
          start_cap = !closed && index.zero? && cap == "square" ? radius : 0
          end_cap = !closed && index == segments.length - 1 && cap == "square" ? radius : 0
          ax, ay, bx, by = a[0] - dx * start_cap, a[1] - dy * start_cap, b[0] + dx * end_cap, b[1] + dy * end_cap
          polygon(result, [[ax + nx, ay + ny], [bx + nx, by + ny], [bx - nx, by - ny], [ax - nx, ay - ny]])
        end
        pairs = (closed ? segments + [segments.first] : segments).each_cons(2)
        pairs.each do |left, right|
          vertex, dx, dy, ex, ey = left[1], left[2], left[3], right[2], right[3]
          cross = dx * ey - dy * ex
          next if cross.abs < 1e-10
          if join == "round"
            disk(result, vertex, radius)
            next
          end
          sign = cross.positive? ? -1 : 1
          a = [vertex[0] - dy * radius * sign, vertex[1] + dx * radius * sign]
          b = [vertex[0] - ey * radius * sign, vertex[1] + ex * radius * sign]
          distance = ((b[0] - a[0]) * ey - (b[1] - a[1]) * ex) / cross
          miter = [a[0] + distance * dx, a[1] + distance * dy]
          if join == "miter" && Math.hypot(miter[0] - vertex[0], miter[1] - vertex[1]) <= radius * limit
            polygon(result, [vertex, a, miter, b])
          else
            polygon(result, [vertex, a, b])
          end
        end
        if !closed && cap == "round"
          disk(result, points.first, radius)
          disk(result, points.last, radius)
        end
      end
      result
    end
    end
  end
end
