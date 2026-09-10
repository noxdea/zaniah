# frozen_string_literal: true

require_relative "test_helper"
require "alhena"

class TextTest < Minitest::Test
  def font
    @font ||= Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
  end
  def test_skyline_atlas_padding_reuse_and_eviction
    atlas = Zaniah::TextSystem::Atlas.new(width: 16, height: 16)
    bitmap = Alhena::Bitmap.new(width: 6, height: 6, left: 0, top: 6, coverage: "\xFF".b * 36)
    entries = 4.times.map { |index| atlas.fetch(index) { bitmap } }
    assert_equal 4, entries.map { |entry| [entry.x, entry.y] }.uniq.length
    assert_equal 0, entries.first.texture.data.getbyte(0)
    assert_same entries.first, atlas.fetch(0) { flunk }
    previous = atlas.generation
    replacement = atlas.fetch(5) { bitmap }
    assert_operator atlas.generation, :>, previous
    refute_same entries.first.texture, replacement.texture
  end
  def test_layout_cache_and_utf8_positions
    system = Zaniah::TextSystem::Renderer.new(font: font, font_db: Zaniah::TextSystem::FontDB.new(paths: []))
    layout = system.layout_line("office AV", size: 20)
    assert_same layout, system.layout_line("office AV", size: 20)
    assert_equal 0, layout.index_for_x(-10)
    assert_equal layout.text.bytesize, layout.index_for_x(layout.width + 10)
    assert_equal layout.width, layout.x_for_index(layout.text.bytesize)
    assert_equal layout.glyphs.sum(&:advance), layout.width
    layout.carets.each { |byte, x| assert_equal byte, layout.index_for_x(x) }
    system.close
  end
  def test_retina_raster_resolution_is_independent_of_logical_layout
    system = Zaniah::TextSystem::Renderer.new(font: font, font_db: Zaniah::TextSystem::FontDB.new(paths: []))
    layout = system.layout_line("A", size: 20)
    one, two = Zaniah::Scene.new, Zaniah::Scene.new
    system.paint_line(one, layout, x: 0, y: 20)
    system.scale_factor = 2
    system.paint_line(two, layout, x: 0, y: 20)
    assert_in_delta one.sprites[2], two.sprites[2], 1
    assert_operator two.sprites[11], :>=, one.sprites[11] * 1.8
    assert_equal layout.width, system.layout_line("A", size: 20).width
    system.close
  end
  def test_colored_atlas_preserves_rgba
    atlas = Zaniah::TextSystem::Atlas.new(width: 8, height: 8, format: :rgba8)
    bitmap = Alhena::ColorBitmap.new(width: 1, height: 1, rgba: [255, 100, 0, 128].pack("C*"))
    entry = atlas.fetch(:smile) { bitmap }
    assert_equal [255, 100, 0, 128], entry.texture.data.byteslice((entry.y * 8 + entry.x) * 4, 4).bytes
  end
end
