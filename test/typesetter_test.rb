# frozen_string_literal: true
require_relative "test_helper"
require "delegate"

class TypesetterTest < Minitest::Test
  class FontCopy < SimpleDelegator
    attr_reader :closed
    def layout_copy = self.class.new(Alhena::Font.new(data, index: index, axes: axis_values))
    def close = @closed = true
  end
  class Database
    attr_reader :closed
    def initialize(font) = @font = font
    def find = @font
    def fallback(_, primary) = primary
    def layout_copy = self.class.new(Alhena::Font.new(@font.data, index: @font.index, axes: @font.axis_values))
    def close = @closed = true
  end
  class DoubleShaper
    attr_reader :calls, :closed
    def initialize = @calls = []
    def shape(glyphs, size:, text:)
      @calls << text
      glyphs.map { |glyph| glyph.with(x: glyph.x * 2, advance: glyph.advance * 2) }
    end
    def layout_copy = self.class.new
    def close = @closed = true
  end

  def test_layout_only_matches_rendering_without_allocating_atlas_textures
    database = Zaniah::TextSystem::FontDB.new(paths: [])
    font = database.find
    system = Zaniah::TextSystem::Renderer.new(font: font, font_db: database)
    typesetter = nil
    Zaniah::GPU::Texture.stub(:new, ->(*) { flunk "layout must not allocate textures" }) do
      typesetter = Zaniah::TextSystem::Typesetter.new(font: font, font_db: database, capacity: 2)
      ["office AV", "日本 é 👩‍💻", "WWiii"].each do |text|
        expected = system.layout_line(text, size: 20)
        actual = typesetter.layout_line(text, size: 20)
        assert_equal expected, actual
        assert_same actual, typesetter.layout_line(text, size: 20)
      end
      refute typesetter.instance_variable_defined?(:@atlas)
      assert_equal 2, typesetter.instance_variable_get(:@cache).length
      refute_same system.shaper, typesetter.shaper
      typesetter.close
      assert_empty typesetter.instance_variable_get(:@cache)
      assert_empty typesetter.instance_variable_get(:@layout_keys)
    end
  ensure
    system&.close
    typesetter&.close
  end

  def test_native_fork_has_independent_fonts_and_caches_without_an_atlas
    system = Zaniah::TextSystem::Renderer.new(font_db: Zaniah::TextSystem::FontDB.new(paths: []))
    copy = nil
    Zaniah::GPU::Texture.stub(:new, ->(*) { flunk "fork must not allocate textures" }) { copy = system.fork(capacity: 2) }
    assert_instance_of Zaniah::TextSystem::Typesetter, copy
    refute_same system.font, copy.font
    assert_equal system.font.data, copy.font.data
    assert copy.font.data.frozen?
    refute_same system.font_db, copy.font_db
    refute_same system.shaper, copy.shaper
    assert_same system.segmenter, copy.segmenter
    ["AV office", "日本 é"].each do |text|
      expected, actual = system.layout_line(text), copy.layout_line(text)
      assert_equal expected.width, actual.width
      assert_equal expected.carets, actual.carets
      assert_equal expected.glyphs.map(&:id), actual.glyphs.map(&:id)
    end
  ensure
    copy&.close
    system&.close
  end

  def test_custom_providers_copy_without_paths_or_shared_layout_state
    font = Zaniah::TextSystem::FontDB.new(paths: []).find
    database, shaper = Database.new(font), DoubleShaper.new
    system = Zaniah::TextSystem::Renderer.new(font_db: database, shaper: shaper)
    copy = system.fork
    refute_same database, copy.font_db
    refute_same shaper, copy.shaper
    line = Thread.new { copy.layout_line("abc") }.value
    assert_equal ["abc"], copy.shaper.calls
    assert_empty shaper.calls
    assert_equal system.layout_line("abc").width, line.width
    copy.close
    assert copy.font_db.closed
    assert copy.shaper.closed
    refute database.closed
    refute shaper.closed
  ensure
    copy&.close
    system&.close
  end

  def test_unsupported_or_invalid_custom_copy_is_an_explicit_error
    shaper = DoubleShaper.new
    shaper.singleton_class.undef_method(:layout_copy)
    system = Zaniah::TextSystem::Renderer.new(font_db: Zaniah::TextSystem::FontDB.new(paths: []), shaper: shaper)
    error = assert_raises(Zaniah::TextSystem::Typesetter::CopyError) { system.fork }
    assert_match(/shaper.*layout_copy/, error.message)
    result = shaper
    shaper.define_singleton_method(:layout_copy) { result }
    error = assert_raises(Zaniah::TextSystem::Typesetter::CopyError) { system.fork }
    assert_match(/independent provider/, error.message)
    refute shaper.closed
    invalid = Object.new
    closed = false
    invalid.define_singleton_method(:close) { closed = true }
    result = invalid
    assert_raises(Zaniah::TextSystem::Typesetter::CopyError) { system.fork }
    assert closed
  ensure
    system&.close
  end

  def test_copied_font_resources_are_owned_by_the_fork
    font = FontCopy.new(Zaniah::TextSystem::FontDB.new(paths: []).find)
    system = Zaniah::TextSystem::Typesetter.new(font: font, font_db: Zaniah::TextSystem::FontDB.new(paths: []))
    copy = system.fork
    assert_equal system.layout_line("ab").width, copy.layout_line("ab").width
    copy.close
    assert copy.font.closed
    refute font.closed
  ensure
    copy&.close
    system&.close
    font&.close
  end
end
