# frozen_string_literal: true

module Zaniah
  module GPU
    class FrameEncoder
      def initialize(device, clear)
        @device, @clear, @scene, @textures = device, clear, Scene.new, {}
      end

      def set_pipeline(pipeline) = @pipeline = pipeline
      def set_uniforms(**values) = @uniforms = values
      def set_texture(slot, texture) = @textures[slot] = texture
      def set_scissor(bounds) = @scissor = bounds

      def draw_instanced(vertex_count:, instance_buffer:, instance_count:)
        raise ArgumentError, "expected quad vertices" unless vertex_count == 4
        raise ArgumentError, "pipeline not set" unless @pipeline
        draw = lambda do
          values = instance_buffer.data.unpack("f*")
          if @pipeline.shader == :quad
            raise ArgumentError, "instance buffer too small" if values.length < instance_count * Scene::QUAD_STRIDE
            instance_count.times do |index|
              quad = values.slice(index * Scene::QUAD_STRIDE, Scene::QUAD_STRIDE)
              color = if quad[24].zero?
                quad[4, 4]
              elsif quad[24] == 1
                Gradient.linear(angle: quad[27], stops: [[quad[25], quad[4, 4]], [quad[26], quad[8, 4]]])
              else
                Gradient.radial(center: quad[28, 2], radius: quad[30], stops: [[quad[25], quad[4, 4]], [quad[26], quad[8, 4]]])
              end
              @scene.quad(*quad.first(4), color: color, radius: quad[12, 4],
                border_width: Edges.new(*quad[20, 4]), border_color: quad[16, 4],
                transform: Transform.new(*quad[32, 6]), border_style: quad[39] == 1 ? :dashed : :solid)
            end
          elsif [:mono_sprite, :poly_sprite].include?(@pipeline.shader)
            raise ArgumentError, "instance buffer too small" if values.length < instance_count * 12
            texture = @textures.fetch(0)
            instance_count.times do |index|
              sprite = values.slice(index * 12, 12)
              @scene.sprite(*sprite.first(4), texture: texture, color: sprite[4, 4], source: Bounds.new(*sprite[8, 4]))
            end
          else
            raise ArgumentError, "unsupported instanced shader #{@pipeline.shader}"
          end
        end
        @scissor ? @scene.clip(@scissor, &draw) : draw.call
      end

      def present = @device.render(@scene, clear: @clear)
    end
  end
end
