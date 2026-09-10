# frozen_string_literal: true

module Zaniah
  class QuadPacker
    attr_reader :bytes

    def initialize = @bytes = String.new(capacity: 1 << 20, encoding: Encoding::BINARY)

    def pack(scene)
      @bytes.clear
      @bytes << scene.quads.pack("f*")
      @bytes
    end
  end
end
