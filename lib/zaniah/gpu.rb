# frozen_string_literal: true

require_relative "gpu/buffer"
require_relative "gpu/texture"
require_relative "gpu/pipeline"
require_relative "gpu/frame_encoder"
require_relative "gpu/software"

module Zaniah
  module GPU
    def self.create(window = nil, backend: :software, width: nil, height: nil)
      return window.create_device(backend) if window && backend != :software
      raise ArgumentError, "backend requires a native window" unless backend == :software
      size = window&.content_size
      Software.new(width || size&.width || 800, height || size&.height || 600)
    end
  end
end
