# frozen_string_literal: true

require_relative "test_helper"

class GifTest < Minitest::Test
  GIF = [
    "GIF89a".b, [1, 1, 0x80, 0, 0].pack("vvCCC"), [0, 0, 0, 255, 0, 0].pack("C*"),
    "!\xf9\x04\x01\x0a\x00\x00\x00".b, ",\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00".b, ";".b
  ].join.b

  def test_decodes_gif_frame_to_rgba
    width, height, frames = Zaniah::GIF.decode(GIF)
    assert_equal [1, 1], [width, height]
    assert_equal 1, frames.length
    assert_equal [0, 0, 0, 255].pack("C4"), frames.first.pixels
    assert_in_delta 0.1, frames.first.delay
  end
end
