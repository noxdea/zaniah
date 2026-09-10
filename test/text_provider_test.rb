# frozen_string_literal: true

require_relative "test_helper"
require "alhena"

class TextProviderTest < Minitest::Test
  def setup
    @configuration = Zaniah.configuration.dup
    @font = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
  end
  def teardown
    Zaniah.configuration.members.each { |key| Zaniah.configuration[key] = @configuration[key] }
  end
  def test_configured_providers_are_used_and_can_be_overridden
    events, font = [], @font
    db = Object.new
    db.define_singleton_method(:find) { events << :find; font }
    db.define_singleton_method(:fallback) { |_, primary| events << :fallback; primary }
    shaper = Object.new
    shaper.define_singleton_method(:shape) do |glyphs, size:, text:|
      events << [:shape, size, text]
      glyphs.map { |glyph| Zaniah::TextSystem::Glyph.new(glyph.font, glyph.id, glyph.start, glyph.finish, glyph.x * 2, glyph.advance * 2) }
    end
    segmenter = Object.new
    segmenter.define_singleton_method(:grapheme_clusters) { |text| events << [:segment, text]; [text] }
    [db, shaper, segmenter].each { |provider| provider.define_singleton_method(:close) { events << :close } }
    Zaniah.configure { |config| config.font_db = db; config.shaper = shaper; config.segmenter = segmenter }
    system = Zaniah::TextSystem::Renderer.new
    line = system.layout_line("abc", size: 18)
    assert_same db, system.font_db
    assert_same shaper, system.shaper
    assert_same segmenter, system.segmenter
    assert_includes events, :find
    assert_includes events, [:shape, 18, "abc"]
    assert_includes events, [:segment, "abc"]
    assert_equal [0, 3], line.carets.map(&:first)
    assert_in_delta @font.advance(@font.glyph_id("a"), size: 18) * 2, line.glyphs.first.advance
    system.close
    assert_equal 3, events.count(:close)
    override = Zaniah::TextSystem::Renderer.new(font: @font, font_db: Zaniah::TextSystem::FontDB.new(paths: []), shaper: :native, segmenter: :native)
    assert_instance_of Zaniah::TextSystem::Shaper, override.shaper
    override.close
  end
  def test_invalid_provider_names_and_objects_fail_immediately
    %i[font_db shaper segmenter].each do |kind|
      [:unsupported, nil, Object.new].each do |value|
        options = {font: @font, font_db: Zaniah::TextSystem::FontDB.new(paths: []), kind => value}
        assert_raises(ArgumentError) { Zaniah::TextSystem::Renderer.new(**options) }
      end
    end
    assert_raises(ArgumentError) { Zaniah::TextSystem::Renderer.new(font: @font, font_raster: :unsupported) }
  end
  def test_native_segmenter_preserves_extended_grapheme_carets
    system = Zaniah::TextSystem::Renderer.new(font: @font, font_db: Zaniah::TextSystem::FontDB.new(paths: []))
    text = "e\u0301x"
    assert_equal [0, 3, 4], system.layout_line(text).carets.map(&:first)
    assert_equal [], Zaniah::Unicode.grapheme_clusters("")
    assert_equal ["👩‍💻"], Zaniah::Unicode.grapheme_clusters("👩‍💻")
    assert_raises(ArgumentError) { system.layout_line("a", size: 0) }
    system.close
  end
  def test_malformed_provider_results_are_rejected
    segmenter = Object.new
    segmenter.define_singleton_method(:grapheme_clusters) { |_| [""] }
    system = Zaniah::TextSystem::Renderer.new(font: @font, segmenter: segmenter)
    assert_raises(Zaniah::Error) { system.layout_line("a") }
    system.close
    shaper = Object.new
    shaper.define_singleton_method(:shape) { |*, **| [:not_a_glyph] }
    system = Zaniah::TextSystem::Renderer.new(font: @font, shaper: shaper)
    assert_raises(Zaniah::Error) { system.layout_line("a") }
    system.close
  end
end
