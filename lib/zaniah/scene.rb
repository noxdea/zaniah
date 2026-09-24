# frozen_string_literal: true

module Zaniah
  # Primitive payloads are flat arrays; command order preserves alpha compositing.
  class Scene
    QUAD_STRIDE = 40
    SPRITE_STRIDE = 13
    SPRITE_INSTANCE_BYTES = 40 * 4
    LAYER_CONTENT = 0
    LAYER_SELECTION = 100_000
    LAYER_FOCUS_RING = 200_000
    LAYER_OVERLAY = 300_000
    LAYER_MODAL = 500_000
    LAYER_POPUP = 1_000_000
    LAYER_TOOLTIP = 1_100_000
    LAYER_DEBUG = 2_000_000
    attr_reader :paths, :commands, :textures, :sprite_batches
    attr_accessor :vector_sink

    def initialize
      @quads, @sprites, @sprite_transforms, @paths, @commands, @textures = [], [], [], [], [], []
      @quad_bytes, @quad_bytes_trusted = +"".b, true
      @quad_ramps, @gradient_ramps = {}, {}
      @gradient_frame_rows, @gradient_overflow_cache = {}, {}
      @gradient_overflow_atlases, @gradient_overflow_count = [], 0
      @sprite_batches, @expanded_batches = [], {}
      @clips, @layers, @transforms, @opacities = [], [LAYER_CONTENT], [Transform.identity], [1.0]
      @colors, @last_layer, @ordered = {}, -Float::INFINITY, true
      @vector_sequence = 0
    end

    def clear
      [@quads, @quad_bytes, @sprites, @sprite_transforms, @paths, @commands, @textures, @clips].each(&:clear)
      @sprite_batches.clear
      @expanded_batches.clear
      @quad_ramps.clear
      @gradient_frame_rows.clear
      @gradient_overflow_cache.clear
      @gradient_overflow_count = 0
      @layers.replace([LAYER_CONTENT])
      @transforms.replace([Transform.identity])
      @opacities.replace([1.0])
      @last_layer, @ordered = -Float::INFINITY, true
      @vector_sequence = 0
      @vector_sink&.clear
      self
    end

    def quad(x, y, width, height, color:, radius: 0, border_width: 0, border_color: "#0000",
      opacity: 1.0, transform: nil, border_style: :solid)
      return self if width <= 0 || height <= 0
      opacity = Float(opacity) * @opacities.last
      raise ArgumentError, "opacity must be between 0 and 1" unless opacity.finite? && opacity.between?(0, 1)
      raise ArgumentError, "border style must be solid or dashed" unless %i[solid dashed].include?(border_style)
      offset = @quads.length
      corners = radius.is_a?(Numeric) ? [radius] * 4 : radius.is_a?(Corners) ? radius.to_h.values : radius.to_a
      borders = border_width.is_a?(Numeric) ? [border_width] * 4 : border_width.is_a?(Edges) ? border_width.to_h.values : border_width.to_a
      raise ArgumentError, "four radii required" unless corners.length == 4
      raise ArgumentError, "four border widths required" unless borders.length == 4
      raise ArgumentError, "border widths must be nonnegative" unless borders.all? { |value| value.is_a?(Numeric) && value >= 0 }
      primary, secondary, gradient, ramp = paint_values(color, opacity)
      matrix = effective_transform(transform)
      values = [x, y, width, height, *primary, *secondary, *corners,
        *opacity_values(border_color, opacity), *borders, *gradient,
        0, *matrix.to_a, 0, border_style == :dashed ? 1 : 0]
      values.pack("f*", buffer: @quad_bytes) if @quad_bytes_trusted
      @quads.concat(values)
      @quad_ramps[offset] = ramp if ramp
      command(:quad, offset)
      record_vector(Vector::Quad, bounds: Bounds.new(x, y, width, height), fill: color.is_a?(Gradient) ? color : Color.parse(color),
        radii: corners.dup.freeze, border: [borders.dup.freeze, Color.parse(border_color)].freeze,
        border_style: border_style, opacity: opacity) if @vector_sink
      self
    end

    def quads
      @quad_bytes_trusted = false
      @quads
    end
    def quad_texture(offset) = @quad_ramps[offset]

    def push_quad(x, y, width, height, bg, radius, border_width, border_color, order = 0)
      layer(order) { quad(x, y, width, height, color: bg, radius: radius,
                          border_width: border_width, border_color: border_color) }
    end

    def sprite(x, y, width, height, texture:, color: "#fff", source: nil)
      source ||= Bounds.new(0, 0, texture.width, texture.height)
      id = @textures.index(texture) || @textures.push(texture).length - 1
      offset = @sprites.length
      @sprites.push(x, y, width, height, *opacity_values(color, @opacities.last), id,
                    source.x, source.y, source.width, source.height)
      @sprite_transforms << @transforms.last
      command(:sprite, offset)
      record_raster(x, y, width, height, texture, color, source) if @vector_sink
      self
    end

    def image(x, y, width, height, image:, texture:, source: nil)
      source ||= Bounds.new(0, 0, texture.width, texture.height)
      if @vector_sink
        record_vector(Vector::Image, image: image, bounds: Bounds.new(x, y, width, height), source: source,
          pixels: @vector_sink.snapshot_pixels(texture), pixel_width: texture.width,
          pixel_height: texture.height, format: texture.format)
        without_vector_recording { sprite(x, y, width, height, texture: texture, source: source) }
      else
        sprite(x, y, width, height, texture: texture, source: source)
      end
      self
    end

    # Prepacked GPU instances retain ordinary sprite alpha/clip/layer ordering.
    def sprite_batch(bytes, texture: nil)
      batch = bytes if bytes.is_a?(SpriteBatch)
      bytes, texture = batch.bytes, batch.texture if batch
      raise ArgumentError, "invalid packed sprite bytes" unless bytes.is_a?(String) && bytes.bytesize % SPRITE_INSTANCE_BYTES == 0
      raise ArgumentError, "packed sprites need a texture" unless texture.is_a?(GPU::Texture)
      return self if bytes.empty?
      batch = nil unless @transforms.last == Transform.identity && @opacities.last == 1
      bytes = transform_batch(bytes, @transforms.last) unless @transforms.last == Transform.identity
      bytes = opacity_batch(bytes, @opacities.last) unless @opacities.last == 1
      @textures << texture unless @textures.include?(texture)
      offset = @sprite_batches.length
      @sprite_batches << (batch && bytes.frozen? ? batch : SpriteBatch.new(bytes.frozen? ? bytes : bytes.dup.freeze, texture))
      command(:sprite_batch, offset)
      if @vector_sink
        bytes.unpack("f*").each_slice(40) do |values|
          source = Bounds.new(values[20] * texture.width, values[21] * texture.height,
            values[22] * texture.width, values[23] * texture.height)
          record_raster(*values.first(4), texture, Color.new(*values[4, 4]), source,
            transform: Transform.new(*values[32, 6]), opacity: 1)
        end
      end
      self
    end

    # Preserve the public flat-sprite inspection API; native packing does not
    # materialize these arrays, while the software renderer can reuse them.
    def sprites
      @sprite_batches.each_index { |index| expand_sprite_batch(index) }
      @sprites
    end
    def sprite_data = @sprites
    def sprite_transform(offset) = @sprite_transforms.fetch(offset / SPRITE_STRIDE)
    def expand_sprite_batch(index)
      @expanded_batches[index] ||= begin
        batch = @sprite_batches.fetch(index)
        texture = batch.texture
        id = @textures.index(texture)
        offset = @sprites.length
        batch.bytes.unpack("f*").each_slice(40) do |values|
          @sprites.push(*values[0, 8], id, values[20] * texture.width, values[21] * texture.height,
                        values[22] * texture.width, values[23] * texture.height)
          @sprite_transforms << Transform.new(*values[32, 6])
        end
        [offset, batch.bytes.bytesize / SPRITE_INSTANCE_BYTES]
      end
    end

    def triangle(points, color:)
      raise ArgumentError, "three points required" unless points.length == 6
      offset = @paths.length
      @paths.push(*points, *opacity_values(color, @opacities.last), *@transforms.last.to_a)
      command(:triangle, offset)
      if @vector_sink
        outline = SVG::Path.parse("M#{points[0]} #{points[1]}L#{points[2]} #{points[3]}L#{points[4]} #{points[5]}Z")
        record_vector(Vector::Path, outline: outline, fill: Color.parse(color), stroke: nil, stroke_width: 0,
          fill_rule: :nonzero, stroke_cap: :round, stroke_join: :round, stroke_miter: 4)
      end
      self
    end

    def path(path, fill: nil, stroke: nil, width: 1, fill_rule: :nonzero,
      stroke_cap: :round, stroke_join: :round, stroke_miter: 4)
      raise ArgumentError, "path needs a fill or stroke" unless fill || stroke
      outline = path.is_a?(String) ? SVG::Path.parse(path) : path.respond_to?(:parse) ? path.parse : path
      if @vector_sink
        record_vector(Vector::Path, outline: outline, fill: fill && Color.parse(fill),
          stroke: stroke && Color.parse(stroke), stroke_width: width, fill_rule: fill_rule,
          stroke_cap: stroke_cap, stroke_join: stroke_join, stroke_miter: stroke_miter)
      end
      without_vector_recording do
        [[fill, nil], [stroke, width]].each do |color, stroke_width|
          next unless color
          bounds, texture = SVG.rasterize_outline(outline, stroke_width: stroke_width,
            stroke_cap: stroke_cap, stroke_join: stroke_join, stroke_miter: stroke_miter, fill_rule: fill_rule)
          sprite(bounds.x, bounds.y, bounds.width, bounds.height, texture: texture, color: color) if texture
        end
      end
      self
    end

    def shadow(x, y, width, height, color: "#0006", blur: 8, radius: 0, spread: 0, inset: false)
      raise ArgumentError, "blur and spread must be finite and nonnegative" unless [blur, spread].all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }
      return self if width <= 0 || height <= 0
      corners = radius.is_a?(Numeric) ? [radius] * 4 : radius.is_a?(Corners) ? radius.to_h.values : radius.to_a
      raise ArgumentError, "four radii required" unless corners.length == 4
      margin = inset ? 0 : spread + blur * 3 + 1
      bounds = Bounds.new(x - margin, y - margin, width + margin * 2, height + margin * 2)
      offset = @quads.length
      values = [bounds.x, bounds.y, bounds.width, bounds.height,
        *opacity_values(color, @opacities.last), *Array.new(4, 0), *corners,
        *Array.new(8, 0), 0, 0, 0, 0, 0, 0, blur, 4, *@transforms.last.to_a, spread, inset ? 1 : 0]
      values.pack("f*", buffer: @quad_bytes) if @quad_bytes_trusted
      @quads.concat(values)
      command(:quad, offset)
      record_vector(Vector::Shadow, bounds: Bounds.new(x, y, width, height), radii: radius.is_a?(Array) ? radius.dup.freeze : radius,
        color: Color.parse(color), blur: blur, spread: spread, inset: inset) if @vector_sink
      self
    end

    def underline(x, y, width, color:, thickness: 1, wave: false)
      record_vector(Vector::Underline, x: x, y: y, width: width, thickness: thickness,
        color: Color.parse(color), wave: wave) if @vector_sink
      without_vector_recording do
        if wave
          width.ceil.times do |i|
            quad(x + i, y + Math.sin(i * Math::PI / 4) * thickness, 1, thickness, color: color)
          end
        else
          quad(x, y, width, thickness, color: color)
        end
      end
      self
    end

    def without_vector_recording
      sink, @vector_sink = @vector_sink, nil
      yield
    ensure
      @vector_sink = sink
    end

    def record_vector(kind, transform: @transforms.last, clip: @clips.last, opacity: @opacities.last, **attributes)
      return unless @vector_sink
      if kind == Vector::Path
        outline = attributes.fetch(:outline).transform(Transform.identity.to_a)
        outline.commands.freeze
        outline.coordinates.freeze
        attributes[:outline] = outline.freeze
      end
      command = kind.new(**attributes, transform: transform, clip: clip,
        opacity: opacity, layer: @layers.last, sequence: @vector_sequence)
      @vector_sequence += 1
      @vector_sink.record(command)
      command
    end

    def clip(bounds)
      @clips << (@clips.empty? ? bounds : @clips.last.intersect(bounds))
      yield
    ensure
      @clips.pop
    end
    def current_clip = @clips.last
    def current_transform = @transforms.last

    def layer(order)
      @layers << [@layers.last, order].max
      yield
    ensure
      @layers.pop
    end

    def push_transform(transform)
      raise ArgumentError, "expected a Transform" unless transform.is_a?(Transform)
      @transforms << @transforms.last.compose(transform)
      pushed = true
      yield
    ensure
      @transforms.pop if pushed
    end

    def push_opacity(opacity)
      opacity = Float(opacity)
      raise ArgumentError, "opacity must be between 0 and 1" unless opacity.finite? && opacity.between?(0, 1)
      @opacities << @opacities.last * opacity
      pushed = true
      yield
    ensure
      @opacities.pop if pushed
    end

    def each_command
      return enum_for(__method__) unless block_given?
      if @ordered
        index = 0
        while index < @commands.length
          yield @commands[index], @commands[index + 1], @commands[index + 3]
          index += 4
        end
        return
      end
      indices = (0...@commands.length).step(4).to_a
      indices.sort_by! { |i| [@commands[i + 2], i] }
      indices.each { |i| yield @commands[i], @commands[i + 1], @commands[i + 3] }
    end

    private

    def record_raster(x, y, width, height, texture, color, source, transform: @transforms.last, opacity: @opacities.last)
      record_vector(Vector::Raster, bounds: Bounds.new(x, y, width, height), pixels: @vector_sink.snapshot_pixels(texture),
        pixel_width: texture.width, pixel_height: texture.height, format: texture.format,
        color: Color.parse(color), source: source, transform: transform, opacity: opacity)
    end

    def packed_quad_bytes
      @quad_bytes.dup if @quad_bytes_trusted
    end

    def effective_transform(transform)
      return @transforms.last unless transform
      raise ArgumentError, "expected a Transform" unless transform.is_a?(Transform)
      @transforms.last.compose(transform)
    end

    def paint_values(value, opacity)
      return [opacity_values(value, opacity), [0, 0, 0, 0], [0, 0, 1, 0, 0, 0, 0], nil] unless value.is_a?(Gradient)
      if value.stops.length > 2
        kind = {linear: 4, radial: 5, conic: 6}.fetch(value.kind)
        center = value.center || [0.5, 0.5]
        texture, row = ramp_for(value)
        return [[1, 1, 1, opacity], [row, 0, 0, 0],
          [kind, 0, 1, value.angle || 0, center[0], center[1], value.radius || 0.5], texture]
      end
      first, last = value.stops
      kind = {linear: 1, radial: 2, conic: 3}.fetch(value.kind)
      center = value.center || [0.5, 0.5]
      [opacity_values(first.last, opacity), opacity_values(last.last, opacity),
        [kind, first.first, last.first, value.angle || 0, center[0], center[1], value.radius || 0.5], nil]
    end

    def ramp_for(gradient)
      cached = @gradient_ramps.delete(gradient)
      if cached
        @gradient_ramps[gradient] = cached
        @gradient_frame_rows[cached] = true
        return [@gradient_atlas, cached]
      end
      return @gradient_overflow_cache[gradient] if @gradient_overflow_cache.key?(gradient)
      @gradient_atlas ||= GPU::Texture.new(256, 256)
      row = if @gradient_ramps.length < 256
        @gradient_ramps.length
      else
        evicted = @gradient_ramps.find { |_key, candidate| !@gradient_frame_rows[candidate] }
        if evicted
          @gradient_ramps.delete(evicted.first)
          evicted.last
        end
      end
      if row
        @gradient_ramps[gradient] = row
        @gradient_frame_rows[row] = true
        texture = @gradient_atlas
      else
        index = @gradient_overflow_count
        @gradient_overflow_count += 1
        row = index % 256
        texture = (@gradient_overflow_atlases[index / 256] ||= GPU::Texture.new(256, 256))
        @gradient_overflow_cache[gradient] = [texture, row]
      end
      stops = gradient.stops
      bytes = String.new(capacity: 1024, encoding: Encoding::BINARY)
      256.times do |index|
        position = index / 255.0
        right = stops.bsearch_index { |stop| stop.first >= position } || stops.length - 1
        left = [right - 1, 0].max
        start_at, start_color = stops[left]
        end_at, end_color = stops[right]
        amount = end_at == start_at ? 1.0 : ((position - start_at) / (end_at - start_at)).clamp(0, 1)
        start_rgba, end_rgba = start_color.to_a, end_color.to_a
        4.times { |channel| bytes << ((start_rgba[channel] + (end_rgba[channel] - start_rgba[channel]) * amount) * 255).round.clamp(0, 255) }
      end
      texture.upload(0, row, 256, 1, bytes)
      [texture, row]
    end

    def opacity_values(value, opacity)
      values = color_values(value)
      return values if opacity == 1
      [values[0], values[1], values[2], values[3] * opacity]
    end

    def transform_batch(bytes, parent)
      values = bytes.unpack("f*")
      (0...values.length).step(40) do |offset|
        matrix = parent.compose(Transform.new(*values.slice(offset + 32, 6)))
        values[offset + 32, 6] = matrix.to_a
      end
      values.pack("f*").freeze
    end

    def opacity_batch(bytes, opacity)
      values = bytes.unpack("f*")
      (0...values.length).step(40) { |offset| values[offset + 7] *= opacity }
      values.pack("f*").freeze
    end

    def color_values(value)
      @colors.clear if @colors.length > 256
      @colors[value] ||= Color.parse(value).to_a.freeze
    end

    def command(kind, offset)
      @ordered = false if @layers.last < @last_layer
      @last_layer = @layers.last
      @commands.push(kind, offset, @layers.last, @clips.last)
    end
  end

end

require_relative "scene/sprite_batch"
require_relative "quad_packer"
require_relative "scene_renderer"
require_relative "vector"
