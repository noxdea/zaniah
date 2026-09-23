# frozen_string_literal: true

module Zaniah
  class Image < Element
    def self.from_bytes(bytes, format: :auto) = new(nil, bytes: bytes, format: format)

    def initialize(path = nil, bytes: nil, format: :auto)
      super()
      bytes ||= File.binread(path)
      raise ArgumentError, "image bytes must be a String" unless bytes.is_a?(String)
      format = :jpeg if format == :jpg
      format = detect_format(bytes) if format == :auto
      width, height, pixels = case format
      when :png
        PNG.decode(bytes)
      when :jpeg
        JPEG.decode(bytes)
      when :gif
        gif_width, gif_height, frames = GIF.decode(bytes)
        @frames = frames
        [gif_width, gif_height, frames.first.pixels]
      else
        raise ArgumentError, "unsupported image format #{format.inspect}"
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

    private

    def detect_format(bytes)
      return :png if bytes.start_with?(PNG::SIGNATURE)
      return :gif if bytes.start_with?("GIF87a", "GIF89a")
      return :jpeg if bytes.start_with?("\xFF\xD8".b)
      raise ArgumentError, "unsupported image format"
    end
  end
end
