# frozen_string_literal: true

module Zaniah
  # Primitive payloads are flat arrays; command order preserves alpha compositing.
  class Scene
    QUAD_STRIDE = 17
    SPRITE_INSTANCE_BYTES = 24 * 4
    attr_reader :quads, :paths, :commands, :textures, :sprite_batches

    def initialize
      @quads, @sprites, @paths, @commands, @textures = [], [], [], [], []
      @sprite_batches, @expanded_batches = [], {}
      @clips, @layers = [], [0]
      @colors, @last_layer, @ordered = {}, -Float::INFINITY, true
    end

    def clear
      [@quads, @sprites, @paths, @commands, @textures, @clips].each(&:clear)
      @sprite_batches.clear
      @expanded_batches.clear
      @layers.replace([0])
      @last_layer, @ordered = -Float::INFINITY, true
      self
    end

    def quad(x, y, width, height, color:, radius: 0, border_width: 0, border_color: "#0000")
      return self if width <= 0 || height <= 0
      offset = @quads.length
      if radius.is_a?(Numeric)
        @quads.push(x, y, width, height, *color_values(color), radius, radius, radius, radius, border_width, *color_values(border_color))
      else
        corners = radius.to_a
        raise ArgumentError, "four radii required" unless corners.length == 4
        @quads.push(x, y, width, height, *color_values(color), *corners, border_width, *color_values(border_color))
      end
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
    def expand_sprite_batch(index)
      @expanded_batches[index] ||= begin
        batch = @sprite_batches.fetch(index)
        texture = batch.texture
        id = @textures.index(texture)
        offset = @sprites.length
        batch.bytes.unpack("f*").each_slice(24) do |values|
          @sprites.push(*values[0, 8], id, values[20] * texture.width, values[21] * texture.height,
                        values[22] * texture.width, values[23] * texture.height)
        end
        [offset, batch.bytes.bytesize / SPRITE_INSTANCE_BYTES]
      end
    end

    def triangle(points, color:)
      raise ArgumentError, "three points required" unless points.length == 6
      offset = @paths.length
      @paths.push(*points, *color_values(color))
      command(:triangle, offset)
      self
    end

    def shadow(x, y, width, height, color: "#0006", blur: 8, radius: 0)
      raise ArgumentError, "blur must be positive" unless blur.positive?
      # A small sequence of expanding translucent rounded rectangles approximates
      # a Gaussian convolution without a temporary render target.
      8.downto(1) do |step|
        spread = blur * step / 8.0
        alpha = Math.exp(-2.0 * (step / 8.0)**2) / 10.0
        quad(x - spread, y - spread, width + 2 * spread, height + 2 * spread,
             color: Color.parse(color).opacity(alpha), radius: radius + spread)
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
