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
    attr_reader :quads, :paths, :commands, :textures, :sprite_batches

    def initialize
      @quads, @sprites, @sprite_transforms, @paths, @commands, @textures = [], [], [], [], [], []
      @sprite_batches, @expanded_batches = [], {}
      @clips, @layers, @transforms = [], [LAYER_CONTENT], [Transform.identity]
      @colors, @last_layer, @ordered = {}, -Float::INFINITY, true
    end

    def clear
      [@quads, @sprites, @sprite_transforms, @paths, @commands, @textures, @clips].each(&:clear)
      @sprite_batches.clear
      @expanded_batches.clear
      @layers.replace([LAYER_CONTENT])
      @transforms.replace([Transform.identity])
      @last_layer, @ordered = -Float::INFINITY, true
      self
    end

    def quad(x, y, width, height, color:, radius: 0, border_width: 0, border_color: "#0000",
      opacity: 1.0, transform: nil, border_style: :solid)
      return self if width <= 0 || height <= 0
      opacity = Float(opacity)
      raise ArgumentError, "opacity must be between 0 and 1" unless opacity.finite? && opacity.between?(0, 1)
      raise ArgumentError, "border style must be solid or dashed" unless %i[solid dashed].include?(border_style)
      offset = @quads.length
      corners = radius.is_a?(Numeric) ? [radius] * 4 : radius.is_a?(Corners) ? radius.to_h.values : radius.to_a
      borders = border_width.is_a?(Numeric) ? [border_width] * 4 : border_width.is_a?(Edges) ? border_width.to_h.values : border_width.to_a
      raise ArgumentError, "four radii required" unless corners.length == 4
      raise ArgumentError, "four border widths required" unless borders.length == 4
      raise ArgumentError, "border widths must be nonnegative" unless borders.all? { |value| value.is_a?(Numeric) && value >= 0 }
      primary, secondary, gradient = paint_values(color, opacity)
      matrix = effective_transform(transform)
      @quads.push(x, y, width, height, *primary, *secondary, *corners,
        *opacity_values(border_color, opacity), *borders, *gradient,
        0, *matrix.to_a, 0, border_style == :dashed ? 1 : 0)
      command(:quad, offset)
      self
    end

    def push_quad(x, y, width, height, bg, radius, border_width, border_color, order = 0)
      layer(order) { quad(x, y, width, height, color: bg, radius: radius,
                          border_width: border_width, border_color: border_color) }
    end

    def sprite(x, y, width, height, texture:, color: "#fff", source: nil)
      source ||= Bounds.new(0, 0, texture.width, texture.height)
      id = @textures.index(texture) || @textures.push(texture).length - 1
      offset = @sprites.length
      @sprites.push(x, y, width, height, *color_values(color), id,
                    source.x, source.y, source.width, source.height)
      @sprite_transforms << @transforms.last
      command(:sprite, offset)
      self
    end

    # Prepacked GPU instances retain ordinary sprite alpha/clip/layer ordering.
    def sprite_batch(bytes, texture: nil)
      batch = bytes if bytes.is_a?(SpriteBatch)
      bytes, texture = batch.bytes, batch.texture if batch
      raise ArgumentError, "invalid packed sprite bytes" unless bytes.is_a?(String) && bytes.bytesize % SPRITE_INSTANCE_BYTES == 0
      raise ArgumentError, "packed sprites need a texture" unless texture.is_a?(GPU::Texture)
      return self if bytes.empty?
      batch = nil unless @transforms.last == Transform.identity
      bytes = transform_batch(bytes, @transforms.last) unless @transforms.last == Transform.identity
      @textures << texture unless @textures.include?(texture)
      offset = @sprite_batches.length
      @sprite_batches << (batch && bytes.frozen? ? batch : SpriteBatch.new(bytes.frozen? ? bytes : bytes.dup.freeze, texture))
      command(:sprite_batch, offset)
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
      @paths.push(*points, *color_values(color), *@transforms.last.to_a)
      command(:triangle, offset)
      self
    end

    def path(path, fill: nil, stroke: nil, width: 1)
      raise ArgumentError, "path needs a fill or stroke" unless fill || stroke
      outline = path.is_a?(String) ? SVG::Path.parse(path) : path.respond_to?(:parse) ? path.parse : path
      [[fill, nil], [stroke, width]].each do |color, stroke_width|
        next unless color
        bounds, texture = SVG.rasterize_outline(outline, stroke_width: stroke_width)
        sprite(bounds.x, bounds.y, bounds.width, bounds.height, texture: texture, color: color) if texture
      end
      self
    end

    def shadow(x, y, width, height, color: "#0006", blur: 8, radius: 0, spread: 0, inset: false)
      raise ArgumentError, "blur and spread must be nonnegative" unless blur >= 0 && spread >= 0
      steps = blur.zero? ? 1 : 8
      steps.downto(1) do |step|
        amount = spread + blur * step / steps.to_f
        alpha = blur.zero? ? 1 : Math.exp(-2.0 * (step / steps.to_f)**2) / 10.0
        tint = Color.parse(color).opacity(alpha)
        if inset
          quad(x, y, width, height, color: "#0000", radius: radius,
            border_width: amount, border_color: tint)
        else
          quad(x - amount, y - amount, width + 2 * amount, height + 2 * amount,
            color: tint, radius: radius.is_a?(Numeric) ? radius + amount : radius)
        end
      end
      self
    end

    def underline(x, y, width, color:, thickness: 1, wave: false)
      return quad(x, y, width, thickness, color: color) unless wave
      width.ceil.times do |i|
        quad(x + i, y + Math.sin(i * Math::PI / 4) * thickness, 1, thickness, color: color)
      end
      self
    end

    def clip(bounds)
      @clips << (@clips.empty? ? bounds : @clips.last.intersect(bounds))
      yield
    ensure
      @clips.pop
    end
    def current_clip = @clips.last

    def layer(order)
      @layers << order
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

    def effective_transform(transform)
      return @transforms.last unless transform
      raise ArgumentError, "expected a Transform" unless transform.is_a?(Transform)
      @transforms.last.compose(transform)
    end

    def paint_values(value, opacity)
      return [opacity_values(value, opacity), [0, 0, 0, 0], [0, 0, 1, 0, 0, 0, 0]] unless value.is_a?(Gradient)
      raise ArgumentError, "rendered gradients require exactly two stops" unless value.stops.length == 2
      raise ArgumentError, "conic gradients are not supported" if value.kind == :conic
      first, last = value.stops
      kind = value.kind == :linear ? 1 : 2
      center = value.center || [0.5, 0.5]
      [opacity_values(first.last, opacity), opacity_values(last.last, opacity),
        [kind, first.first, last.first, value.angle || 0, center[0], center[1], value.radius || 0.5]]
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
