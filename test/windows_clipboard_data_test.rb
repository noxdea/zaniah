# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/windows/clipboard_data"

class WindowsClipboardDataTest < Minitest::Test
  Data = Zaniah::Platform::Windows::ClipboardData

  def test_cf_html_offsets_are_utf8_byte_offsets_and_round_trip
    fragment = "<b>日本語 &amp; emoji 😀</b>"
    bytes = Data.format_html(fragment)
    offsets = %w[StartHTML EndHTML StartFragment EndFragment].to_h { |key| [key, bytes[/^#{key}:(\d+)/, 1].to_i] }
    assert_equal "<html>", bytes.byteslice(offsets["StartHTML"], 6)
    assert_equal bytes.bytesize, offsets["EndHTML"]
    assert_equal fragment.b, bytes.byteslice(offsets["StartFragment"]...offsets["EndFragment"])
    assert_equal fragment, Data.parse_html(bytes)
    assert_equal fragment, Data.parse_html(bytes + "\0")
  end

  def test_cf_html_rejects_corrupt_ranges_and_invalid_utf8
    bytes = Data.format_html("<b>A</b>")
    assert_raises(ArgumentError) { Data.parse_html(bytes.sub(/StartFragment:\d+/, "StartFragment:9999999999")) }
    assert_raises(ArgumentError) { Data.parse_html(bytes.sub(/EndHTML:\d+/, "EndHTML:0000000001")) }
    assert_raises(ArgumentError) { Data.parse_html("not CF_HTML") }
    assert_raises(ArgumentError) { Data.parse_html(bytes.sub("<b>A</b>", "\xff".b)) }
  end

  def test_file_uris_convert_to_hdrop_and_back
    paths = ["C:\\My file\\日本語.txt", "\\\\server\\share\\a.txt"]
    uris = Data.uri_list(paths)
    assert_equal paths, Data.file_paths(uris)
    drop = Data.hdrop(paths)
    assert_equal 20, drop.unpack1("L<")
    assert_equal 1, drop.byteslice(16, 4).unpack1("L<")
    assert drop.byteslice(20..).end_with?("\0\0\0\0".b)
    assert_nil Data.file_paths("https://example.com/a\r\n")
  end

  def test_cf_dibv5_32bit_bottom_up_to_png
    header = [124, 1, 2, 1, 32, 3].pack("L<l<l<S<S<L<") + "\0".b * 20
    header << [0x00ff0000, 0x0000ff00, 0x000000ff, 0xff000000].pack("L<4")
    header << "\0".b * (124 - header.bytesize)
    pixels = [0xff0000ff, 0xffff0000].pack("L<2") # bottom blue, top red
    width, height, rgba = Zaniah::PNG.decode(Data.dibv5_to_png(header + pixels))
    assert_equal [1, 2], [width, height]
    assert_equal [255, 0, 0, 255, 0, 0, 255, 255], rgba.bytes
    assert_raises(ArgumentError) { Data.dibv5_to_png(header + pixels.byteslice(0, 4)) }
  end
end
