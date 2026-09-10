# frozen_string_literal: true

module Zaniah
  module GPU
    class Texture
      attr_reader :width, :height, :format, :data, :revision

      def initialize(width, height, format: :rgba8, data: nil)
        raise ArgumentError, "invalid texture" unless width.is_a?(Integer) && height.is_a?(Integer) && width.positive? && height.positive? && [:r8, :rgba8].include?(format)
        @width, @height, @format = width, height, format
        @revision = 0
        @channels = format == :r8 ? 1 : 4
        @data = data ? data.b.dup : "\0".b * (width * height * @channels)
        raise ArgumentError, "incorrect texture data size" unless @data.bytesize == width * height * @channels
      end

      def upload(x, y, width, height, bytes)
        raise ArgumentError, "texture write out of bounds" if x.negative? || y.negative? || width.negative? || height.negative? || x + width > @width || y + height > @height
        raise ArgumentError, "incorrect upload size" unless bytes.bytesize == width * height * @channels
        height.times do |row|
          @data[((y + row) * @width + x) * @channels, width * @channels] = bytes.byteslice(row * width * @channels, width * @channels)
        end
        @revision += 1
        self
      end

      def release
        @data.clear
        @revision += 1
      end
    end
  end
end
