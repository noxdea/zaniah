# frozen_string_literal: true

require_relative "gpu/buffer"
require_relative "gpu/texture"
require_relative "gpu/pipeline"
require_relative "gpu/frame_encoder"
require_relative "gpu/software"

module Zaniah
  module GPU
    def self.create(window = nil, backend: :software, width: nil, height: nil)
      size = window&.content_size
      return window.create_device(backend) if window && !%i[software vulkan].include?(backend)
      dimensions = [(width || size&.width || 800).to_i, (height || size&.height || 600).to_i]
      return Software.new(*dimensions) if backend == :software
      if backend == :vulkan
        require_relative "gpu/vulkan"
        return Vulkan.new(width: dimensions[0], height: dimensions[1])
      end
      raise ArgumentError, "backend requires a native window"
    end
  end
end
