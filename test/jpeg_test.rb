# frozen_string_literal: true

require_relative "test_helper"

class JpegTest < Minitest::Test
  def test_decodes_grayscale_and_orients_exif_images
    width, height, rgba = Zaniah::JPEG.decode(jpeg(width: 16, height: 8, orientation: 6))
    assert_equal [8, 16], [width, height]
    assert_equal 16 * 8 * 4, rgba.bytesize
    assert_equal [128, 128, 128, 255].pack("C4"), rgba.byteslice(0, 4)
    assert_equal 128, rgba.getbyte((width * height - 1) * 4)
  end

  def test_decodes_neutral_ycbcr_at_444_422_and_420_sampling
    [[1, 1], [2, 1], [2, 2]].each do |y_sampling|
      width, height, rgba = Zaniah::JPEG.decode(jpeg(width: 8, height: 8, color: true, sampling: y_sampling))
      assert_equal [8, 8], [width, height]
      assert_equal 8 * 8 * 4, rgba.bytesize
      assert_equal [128, 128, 128, 255].pack("C4"), rgba.byteslice(0, 4)
    end
  end

  def test_converts_non_neutral_ycbcr_samples
    _width, _height, rgba = Zaniah::JPEG.decode(jpeg(width: 8, height: 8, color: true, color_delta: [0, 0, 64]))
    assert_equal [139, 122, 128, 255].pack("C4"), rgba.byteslice(0, 4)
  end

  def test_applies_all_eight_exif_orientations
    expected = {
      1 => [[16, 8], [0, 0]], 2 => [[16, 8], [15, 0]],
      3 => [[16, 8], [15, 7]], 4 => [[16, 8], [0, 7]],
      5 => [[8, 16], [0, 0]], 6 => [[8, 16], [7, 0]],
      7 => [[8, 16], [7, 15]], 8 => [[8, 16], [0, 15]]
    }
    expected.each do |orientation, (dimensions, source_origin)|
      width, height, rgba = Zaniah::JPEG.decode(jpeg(width: 16, height: 8, orientation: orientation, gray_diffs: [0, 64]))
      assert_equal dimensions, [width, height]
      x, y = source_origin
      assert_equal [128, 128, 128, 255].pack("C4"), rgba.byteslice((y * width + x) * 4, 4)
    end
  end

  def test_image_auto_detects_jpeg_bytes_and_rejects_progressive
    bytes = jpeg(width: 8, height: 8)
    image = Zaniah::Image.from_bytes(bytes)
    texture = image.instance_variable_get(:@texture)
    assert_equal [8, 8], [texture.width, texture.height]
    assert_raises(Zaniah::JPEG::Error) { Zaniah::JPEG.decode("\xFF\xD8\xFF\xC2\x00\x02".b) }
    assert_raises(Zaniah::JPEG::Error) { Zaniah::JPEG.decode(bytes.byteslice(0...-2)) }
  end

  def test_rejects_oversubscribed_huffman_tables
    assert_raises(Zaniah::JPEG::Error) { Zaniah::JPEG::Huffman.new([3, *Array.new(15, 0)], [0, 1, 2]) }
  end

  private

  def jpeg(width:, height:, color: false, sampling: [1, 1], orientation: nil, gray_diffs: nil, color_delta: nil)
    components = color ? [[1, sampling[0], sampling[1]], [2, 1, 1], [3, 1, 1]] : [[1, 1, 1]]
    blocks = if color
      mcu_w, mcu_h = sampling[0] * 8, sampling[1] * 8
      across, down = (width + mcu_w - 1) / mcu_w, (height + mcu_h - 1) / mcu_h
      across * down * components.sum { |_, h, v| h * v }
    else
      ((width + 7) / 8) * ((height + 7) / 8)
    end
    dqt = segment(0xdb, [0, *Array.new(64, 1)].pack("C*"))
    dc = [0, 1, 1, *Array.new(14, 0), 0, 7]
    ac = [0x10, 1, *Array.new(15, 0), 0]
    dht = segment(0xc4, (dc + ac).pack("C*"))
    sof_payload = [8, height, width, components.length].pack("CnnC")
    components.each { |id, h, v| sof_payload << [id, (h << 4) | v, 0].pack("C3") }
    sof = segment(0xc0, sof_payload)
    app1 = orientation ? segment(0xe1, exif_orientation(orientation)) : "".b
    sos_payload = [components.length].pack("C")
    components.each { |id, _h, _v| sos_payload << [id, 0].pack("C2") }
    sos_payload << [0, 63, 0].pack("C3")
    diffs = if color
      first_blocks = []
      (across * down).times.flat_map do
        components.flat_map do |id, h, v|
          Array.new(h * v) do |index|
            diff = color_delta && !first_blocks.include?(id) && index.zero? ? color_delta[id - 1] : 0
            first_blocks << id
            diff
          end
        end
      end
    else
      gray_diffs || Array.new(blocks, 0)
    end
    entropy_bits = diffs.map { |diff| dc_block_bits(diff) }.join
    entropy_bits << "1" * ((8 - entropy_bits.length % 8) % 8)
    "\xFF\xD8".b + dqt + dht + app1 + sof + segment(0xda, sos_payload) + entropy_bits.scan(/.{8}/).map { |byte| byte.to_i(2) }.pack("C*") + "\xFF\xD9".b
  end

  def dc_block_bits(diff)
    size = diff.abs.bit_length
    huffman = {0 => "0", 7 => "10"}.fetch(size)
    amplitude = diff.negative? ? (1 << size) - 1 + diff : diff
    huffman + (size.zero? ? "" : amplitude.to_s(2).rjust(size, "0")) + "0"
  end

  def segment(marker, data)
    "\xFF".b + [marker, data.bytesize + 2].pack("Cn") + data
  end

  def exif_orientation(value)
    tiff = "II".b + [42].pack("v") + [8].pack("V") + [1, 0x0112, 3].pack("v3") +
      [1].pack("V") + [value, 0].pack("v2") + [0].pack("V")
    "Exif\0\0".b + tiff
  end
end
