# frozen_string_literal: true

module Zaniah
  module TextSystem
    # Bounded LRU of single-line R8 textures generated from Alhena outlines.
    class LowResolutionTextCache
      MAX_PIXELS = 16_777_216
      private_constant :MAX_PIXELS

      attr_reader :width, :height, :scale, :capacity, :max_bytes

      def initialize(width:, height: 2, scale: 0.1, capacity: 4096, max_bytes: 8 << 20)
        dimensions = [width, height]
        unless dimensions.all? { |value| value.is_a?(Integer) && value.positive? } && width * height <= MAX_PIXELS
          raise ArgumentError, "invalid or excessively large texture dimensions"
        end
        scale = Float(scale) if scale.is_a?(Numeric) && scale.real?
        raise ArgumentError, "scale must be positive and finite" unless scale.is_a?(Float) && scale.finite? && scale.positive?
        raise ArgumentError, "capacity must be positive" unless capacity.is_a?(Integer) && capacity.positive?
        raise ArgumentError, "max_bytes must be positive" unless max_bytes.is_a?(Integer) && max_bytes.positive?

        require "alhena"
        @width, @height, @scale = width, height, scale
        @capacity, @max_bytes, @bytesize = capacity, max_bytes, 0
        @entry_bytes = width * height
        @rasterizer = Alhena::Rasterizer.new(width: 1, height: 1)
        @entries, @mutex = {}, Mutex.new
      end

      def size = @mutex.synchronize { @entries.size }
      def bytesize = @mutex.synchronize { @bytesize }
      def closed? = @mutex.synchronize { !!@closed }

      def texture(line, outlines:)
        validate_line(line)
        @mutex.synchronize do
          ensure_open
          cached = @entries.delete(line)
          return @entries[line] = cached if cached

          bitmap = @rasterizer.fill_downsampled(outlines, scale: @scale, width: @width, height: @height)
          texture = GPU::Texture.new(@width, @height, format: :r8, data: bitmap.coverage)
          cache(line, texture)
        end
      end

      def invalidate(line)
        validate_line(line)
        @mutex.synchronize do
          ensure_open
          @bytesize -= @entry_bytes if @entries.delete(line)
        end
        self
      end

      def clear
        @mutex.synchronize do
          ensure_open
          @entries.clear
          @bytesize = 0
        end
        self
      end

      def close
        @mutex.synchronize do
          unless @closed
            @entries.clear
            @bytesize = 0
            @closed = true
          end
        end
        self
      end

      private

      def validate_line(line)
        raise ArgumentError, "line must be a nonnegative integer" unless line.is_a?(Integer) && line >= 0
      end

      def ensure_open
        raise Error, "low-resolution text cache is closed" if @closed
      end

      def cache(line, texture)
        return texture if @entry_bytes > @max_bytes

        @entries[line] = texture
        @bytesize += @entry_bytes
        while @entries.length > @capacity || @bytesize > @max_bytes
          @entries.shift
          @bytesize -= @entry_bytes
        end
        texture
      end
    end
  end
end
