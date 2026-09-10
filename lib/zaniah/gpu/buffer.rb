# frozen_string_literal: true

module Zaniah
  module GPU
    class Buffer
      attr_reader :size, :usage, :data

      def initialize(size, usage: :vertex, mutable: true)
        raise ArgumentError, "invalid buffer size" unless size.is_a?(Integer) && size >= 0
        @size, @usage, @mutable = size, usage, mutable
        @data = "\0".b * size
      end

      def write(bytes, offset: 0)
        raise ArgumentError, "buffer write out of bounds" if offset.negative? || offset + bytes.bytesize > @size
        @data[offset, bytes.bytesize] = bytes
        self
      end

      def release = @data.clear
    end
  end
end
