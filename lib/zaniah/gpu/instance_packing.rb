# frozen_string_literal: true

module Zaniah
  module GPU
    # Consecutive commands only are batched, preserving alpha and layer order.
    module InstancePacking
      STRIDE = 24
      def self.pack(scene)
        data, batches, bytes = [], [], "".b
        scene.each_command do |kind, offset, clip|
          texture = nil
          first = bytes.bytesize / (STRIDE * 4) + data.length / STRIDE
          count = 1
          case kind
          when :quad
            q, i = scene.quads, offset
            data.push(q[i], q[i+1], q[i+2], q[i+3], q[i+4], q[i+5], q[i+6], q[i+7],
              q[i+8], q[i+9], q[i+10], q[i+11], q[i+13], q[i+14], q[i+15], q[i+16], q[i+12], 0, 0, 0, 0, 0, 0, 0)
          when :sprite
            s, i = scene.sprite_data, offset
            texture = scene.textures.fetch(s[i+8])
            data.push(s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5], s[i+6], s[i+7],
              0, 0, 0, 0, 0, 0, 0, 0, 0, texture.format == :r8 ? 1 : 2, 0, 0,
              s[i+9].to_f / texture.width, s[i+10].to_f / texture.height,
              s[i+11].to_f / texture.width, s[i+12].to_f / texture.height)
          when :sprite_batch
            unless data.empty?
              bytes << data.pack("f*")
              data.clear
            end
            batch = scene.sprite_batches.fetch(offset)
            bytes << batch.bytes
            kind, texture = :sprite, batch.texture
            count = batch.bytes.bytesize / (STRIDE * 4)
          when :triangle
            p, i = scene.paths, offset
            data.push(p[i], p[i+1], p[i+2], p[i+3], p[i+6], p[i+7], p[i+8], p[i+9],
              p[i+4], p[i+5], 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0)
          else raise ArgumentError, "unsupported primitive #{kind}"
          end
          previous = batches.last&.first
          if previous && previous[0] == kind && previous[1].equal?(texture) && previous[2] == clip
            batches.last[2] += count
          else
            batches << [[kind, texture, clip], first, count]
          end
        end
        bytes << data.pack("f*") unless data.empty?
        [bytes, batches]
      end
    end
  end
end
