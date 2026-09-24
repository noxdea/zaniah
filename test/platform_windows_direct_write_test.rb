# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/windows/direct_write"

class WindowsDirectWriteTest < Minitest::Test
  def setup
    skip "DirectWrite requires Windows" unless RUBY_PLATFORM.match?(/mswin|mingw/)
    @path = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)
    @db = Zaniah::TextSystem::FontDB.new(paths: [@path])
    @font = @db.open(@path)
    @raster = Zaniah::Platform::Windows::DirectWrite.new(font_db: @db)
  end

  def teardown
    @raster&.close
  end

  def test_file_and_memory_fonts_produce_grayscale_and_cleartype_bitmaps
    glyph = @font.glyph_id("A".ord)
    gray = @raster.rasterize(@font, glyph, size: 24, subpixel_x: 0.25)
    assert_operator gray.width, :>, 0
    assert_operator gray.height, :>, 0
    assert_equal 1, gray.channels
    assert gray.coverage.bytes.any?(&:positive?)

    memory_font = Alhena::Font.open(@path)
    assert_nil @db.path_for(memory_font)
    clear = @raster.rasterize(memory_font, memory_font.glyph_id("A".ord),
      size: 24, antialias: :cleartype)
    assert_equal 3, clear.channels
    assert_equal clear.width * clear.height * 3, clear.coverage.bytesize
    assert clear.coverage.bytes.any?(&:positive?)
  end

  def test_renderer_selects_directwrite_without_changing_default
    renderer = Zaniah::TextSystem::Renderer.new(font: @font, font_db: @db,
      font_raster: :directwrite)
    assert_instance_of Zaniah::Platform::Windows::DirectWrite,
      renderer.instance_variable_get(:@rasters)
    line = renderer.layout_line("DirectWrite", size: 16)
    assert_operator line.glyphs.length, :>, 0
  ensure
    renderer&.close
  end
end

class DirectWriteValidationTest < Minitest::Test
  def test_invalid_arguments_are_rejected_before_native_calls
    raster = Zaniah::Platform::Windows::DirectWrite.allocate
    raster.instance_variable_set(:@factory, 1)
    font = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
    assert_raises(ArgumentError) { raster.rasterize(font, 1, size: 0) }
    assert_raises(ArgumentError) { raster.rasterize(font, -1, size: 16) }
    assert_raises(ArgumentError) { raster.rasterize(font, 1, size: 16, subpixel_x: Float::NAN) }
    assert_raises(ArgumentError) { raster.rasterize(font, 1, size: 16, antialias: :unknown) }
  end
end
