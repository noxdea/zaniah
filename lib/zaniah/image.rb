# frozen_string_literal: true

module Zaniah
  class Image < Element
    def initialize(path)
      super()
      width, height, pixels = PNG.decode(File.binread(path))
      @texture = GPU::Texture.new(width, height, data: pixels)
    end

    def request_layout(_cx)
      @layout_node = Layout::Node.new(style: @style, measure: ->(_width, _height) { [@texture.width, @texture.height] })
    end

    def paint(bounds, _state, _prepaint, cx)
      cx.scene.sprite(bounds.x, bounds.y, bounds.width, bounds.height, texture: @texture)
    end
  end
end
