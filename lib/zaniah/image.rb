# frozen_string_literal: true

module Zaniah
  class Image < Element
    def initialize(path)
      super()
      bytes = File.binread(path)
      width, height, pixels = if bytes.start_with?(PNG::SIGNATURE)
        PNG.decode(bytes)
      elsif bytes.start_with?("GIF87a", "GIF89a")
        gif_width, gif_height, frames = GIF.decode(bytes)
        @frames = frames
        [gif_width, gif_height, frames.first.pixels]
      else
        raise ArgumentError, "unsupported image format"
      end
      @texture = GPU::Texture.new(width, height, data: pixels)
    end

    attr_reader :frames

    def request_layout(_cx)
      @layout_node = Layout::Node.new(style: @style, measure: ->(_width, _height) { [@texture.width, @texture.height] })
    end

    def paint(bounds, _state, _prepaint, cx)
      cx.scene.sprite(bounds.x, bounds.y, bounds.width, bounds.height, texture: @texture)
    end
  end
end
