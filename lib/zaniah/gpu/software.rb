# frozen_string_literal: true

module Zaniah
  module GPU
    class Software
      attr_reader :width, :height, :pixels

      def initialize(width, height)
        resize(width, height)
      end

      def resize(width, height)
        raise ArgumentError, "invalid viewport" unless width.positive? && height.positive? && width * height <= 32_000_000
        @width, @height = width.to_i, height.to_i
        @viewport = Bounds.new(0, 0, @width, @height)
        @pixels = "\0".b * (@width * @height * 4)
      end

      def create_texture(width, height, **options) = Texture.new(width, height, **options)
      def create_buffer(size, **options) = Buffer.new(size, **options)
      def create_pipeline(shader:, blend: :premultiplied) = Pipeline.new(shader, blend)
      def begin_frame(clear: "#0000") = FrameEncoder.new(self, clear)

      def render(scene, clear: "#0000")
        @pixels.replace(Color.parse(clear).to_a.map { |value| (value.clamp(0, 1) * 255).round }.pack("C4") * (@width * @height))
        scene.each_command do |kind, offset, clip|
          bounds = clip ? @viewport.intersect(clip) : @viewport
          case kind
          when :quad then draw_quad(scene.quads, offset, bounds)
          when :sprite then draw_sprite(scene, offset, bounds)
          when :sprite_batch
            first, count = scene.expand_sprite_batch(offset)
            count.times { |index| draw_sprite(scene, first + index * 13, bounds) }
          when :triangle then draw_triangle(scene.paths, offset, bounds)
          end
        end
        @pixels
      end

      def write_png(path) = PNG.write(path, @width, @height, @pixels)
      def release = @pixels.clear

      private

      def draw_quad(data, offset, clip)
        values = data.slice(offset, Scene::QUAD_STRIDE)
        x, y, width, height = values.first(4)
        color, secondary = values[4, 4], values[8, 4]
        radii, border_color, borders = values[12, 4], values[16, 4], values[20, 4]
        gradient = values[24, 7]
        matrix = Transform.new(*values[32, 6])
        bounds = transformed_bounds(x, y, width, height, matrix).intersect(clip)
        if matrix.b.zero? && matrix.c.zero? && borders.all?(&:zero?) && color[3] == 1 &&
            radii.all?(&:zero?) && gradient[0].zero? &&
            [bounds.x, bounds.y, bounds.width, bounds.height].all? { |value| value == value.to_i }
          fill_rect(bounds, *color.first(3))
          return
        end
        gradient = gradient_parameters(gradient)
        if matrix == Transform.identity && borders.all?(&:zero?) && radii.all?(&:zero?) &&
            color[3] == 1 && secondary[3] == 1 && gradient[0] == 1 &&
            fill_axis_gradient(bounds, x, y, width, height, color, secondary, gradient)
          return
        end
        inverse = matrix.inverse
        top, bottom = [bounds.y.floor, 0].max, [bounds.bottom.ceil, @height].min
        left, right = [bounds.x.floor, 0].max, [bounds.right.ceil, @width].min
        pixel_y = top
        while pixel_y < bottom
          pixel_x = left
          while pixel_x < right
            point = inverse.apply(Point.new(pixel_x + 0.5, pixel_y + 0.5))
            local_x, local_y = point.x - x, point.y - y
            radius = local_y < height / 2.0 ? (local_x < width / 2.0 ? radii[0] : radii[1]) : (local_x < width / 2.0 ? radii[3] : radii[2])
            radius = radius.clamp(0, [width, height].min / 2.0)
            quad_x = (local_x - width / 2.0).abs - width / 2.0 + radius
            quad_y = (local_y - height / 2.0).abs - height / 2.0 + radius
            distance = Math.sqrt([quad_x, 0].max**2 + [quad_y, 0].max**2) + [[quad_x, quad_y].max, 0].min - radius
            coverage = (0.5 - distance).clamp(0, 1)
            if coverage.positive?
              fill = gradient[0].zero? ? color : mix(color, secondary, gradient_offset(gradient, local_x, local_y, width, height))
              edge = [local_y, width - local_x, height - local_y, local_x].each_with_index.min_by(&:first).last
              border = borders[edge]
              dashed = values[39] == 1 && ((edge.odd? ? local_y : local_x) % 6) >= 3
              fill = border_color if border.positive? && distance >= -border && !dashed
              blend(pixel_x, pixel_y, fill[0], fill[1], fill[2], fill[3] * coverage)
            end
            pixel_x += 1
          end
          pixel_y += 1
        end
      end

      def fill_rect(bounds, red, green, blue)
        left, right = [bounds.x.to_i, 0].max, [bounds.right.to_i, @width].min
        top, bottom = [bounds.y.to_i, 0].max, [bounds.bottom.to_i, @height].min
        return if left >= right || top >= bottom
        row = [red, green, blue, 1].map { |value| (value.clamp(0, 1) * 255).round }.pack("C4") * (right - left)
        (top...bottom).each { |pixel_y| @pixels[pixel_y * @width * 4 + left * 4, row.bytesize] = row }
      end

      def fill_axis_gradient(bounds, x, y, width, height, color, secondary, gradient)
        left, right = [bounds.x.floor, 0].max, [bounds.right.ceil, @width].min
        top, bottom = [bounds.y.floor, 0].max, [bounds.bottom.ceil, @height].min
        return true if left >= right || top >= bottom
        cosine, sine = gradient[3], gradient[4]
        if sine.abs < 1e-10
          bytes = []
          (left...right).each do |pixel_x|
            amount = gradient_offset(gradient, pixel_x + 0.5 - x, 0.5, width, height)
            bytes.concat(gradient_pixel(color, secondary, amount))
          end
          row = bytes.pack("C*")
          (top...bottom).each { |pixel_y| @pixels[pixel_y * @width * 4 + left * 4, row.bytesize] = row }
        elsif cosine.abs < 1e-10
          (top...bottom).each do |pixel_y|
            amount = gradient_offset(gradient, 0.5, pixel_y + 0.5 - y, width, height)
            row = gradient_pixel(color, secondary, amount).pack("C4") * (right - left)
            @pixels[pixel_y * @width * 4 + left * 4, row.bytesize] = row
          end
        else
          return false
        end
        true
      end

      def gradient_pixel(left, right, amount)
        3.times.map { |index| ((left[index] + (right[index] - left[index]) * amount).clamp(0, 1) * 255).round } << 255
      end

      def draw_sprite(scene, offset, clip)
        x, y, width, height, red, green, blue, alpha, id, source_x, source_y, source_width, source_height = scene.sprite_data.slice(offset, Scene::SPRITE_STRIDE)
        return if width <= 0 || height <= 0
        texture = scene.textures.fetch(id)
        matrix = scene.sprite_transform(offset)
        inverse = matrix.inverse
        bounds = transformed_bounds(x, y, width, height, matrix).intersect(clip)
        ([bounds.y.ceil, 0].max...[bounds.bottom.ceil, @height].min).each do |pixel_y|
          ([bounds.x.ceil, 0].max...[bounds.right.ceil, @width].min).each do |pixel_x|
            point = inverse.apply(Point.new(pixel_x + 0.5, pixel_y + 0.5))
            next unless point.x >= x && point.y >= y && point.x < x + width && point.y < y + height
            texture_x = (source_x + (point.x - x) * source_width / width).floor.clamp(0, texture.width - 1)
            texture_y = (source_y + (point.y - y) * source_height / height).floor.clamp(0, texture.height - 1)
            index = texture_y * texture.width + texture_x
            if texture.format == :r8
              blend(pixel_x, pixel_y, red, green, blue, alpha * texture.data.getbyte(index) / 255.0)
            else
              pixel = index * 4
              blend(pixel_x, pixel_y, red * texture.data.getbyte(pixel) / 255.0,
                green * texture.data.getbyte(pixel + 1) / 255.0,
                blue * texture.data.getbyte(pixel + 2) / 255.0,
                alpha * texture.data.getbyte(pixel + 3) / 255.0)
            end
          end
        end
      end

      def draw_triangle(data, offset, clip)
        x0, y0, x1, y1, x2, y2, red, green, blue, alpha, *transform = data.slice(offset, 16)
        matrix = Transform.new(*transform)
        x0, y0, x1, y1, x2, y2 = [[x0, y0], [x1, y1], [x2, y2]].flat_map do |x, y|
          matrix.apply(Point.new(x, y)).to_a
        end
        area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)
        return if area.zero?
        bounds = Bounds.new([x0, x1, x2].min, [y0, y1, y2].min,
          [x0, x1, x2].max - [x0, x1, x2].min,
          [y0, y1, y2].max - [y0, y1, y2].min).intersect(clip)
        (bounds.y.floor...bounds.bottom.ceil).each do |pixel_y|
          (bounds.x.floor...bounds.right.ceil).each do |pixel_x|
            x, y = pixel_x + 0.5, pixel_y + 0.5
            u = ((x1 - x) * (y2 - y) - (y1 - y) * (x2 - x)) / area.to_f
            v = ((x2 - x) * (y0 - y) - (y2 - y) * (x0 - x)) / area.to_f
            blend(pixel_x, pixel_y, red, green, blue, alpha) if u >= 0 && v >= 0 && u + v <= 1
          end
        end
      end

      def blend(x, y, red, green, blue, alpha)
        return if alpha <= 0
        index = (y * @width + x) * 4
        alpha = alpha.clamp(0, 1)
        destination_alpha = @pixels.getbyte(index + 3) / 255.0
        combined_alpha = alpha + destination_alpha * (1 - alpha)
        [red, green, blue].each_with_index do |value, channel|
          result = (value * alpha + @pixels.getbyte(index + channel) / 255.0 * destination_alpha * (1 - alpha)) / combined_alpha
          @pixels.setbyte(index + channel, (result.clamp(0, 1) * 255).round)
        end
        @pixels.setbyte(index + 3, (combined_alpha * 255).round)
      end

      def transformed_bounds(x, y, width, height, matrix)
        points = [[x, y], [x + width, y], [x, y + height], [x + width, y + height]].map do |px, py|
          matrix.apply(Point.new(px, py))
        end
        left, right = points.map(&:x).minmax
        top, bottom = points.map(&:y).minmax
        Bounds.new(left, top, right - left, bottom - top)
      end

      def gradient_parameters(values)
        kind, first, last, angle, center_x, center_y, radius = values
        radians = angle * Math::PI / 180
        [kind, first, 1.0 / [last - first, Float::EPSILON].max, Math.cos(radians), Math.sin(radians), center_x, center_y, radius]
      end

      def gradient_offset(gradient, x, y, width, height)
        kind, first, scale, cosine, sine, center_x, center_y, radius = gradient
        nx, ny = x / width, y / height
        raw = kind == 1 ? (nx - 0.5) * cosine + (ny - 0.5) * sine + 0.5 : Math.hypot(nx - center_x, ny - center_y) / radius
        ((raw - first) * scale).clamp(0, 1)
      end

      def mix(left, right, amount)
        4.times.map { |index| left[index] + (right[index] - left[index]) * amount }
      end
    end
  end
end
