# frozen_string_literal: true

require_relative "test_helper"

class BidiLayoutTest < Minitest::Test
  class Font
    def units_per_em = 1
    def ascent = 1
    def descent = 0
    def glyph_id(character, variation_selector: nil) = character.is_a?(String) ? character.ord : character
    def advance(_id, size:) = size.to_f
    def tables = {}
  end

  class Database
    def initialize(font) = @font = font
    def find = @font
    def fallback(_codepoint, _primary) = @font
  end

  class LegacyShaper
    attr_reader :calls
    def initialize = @calls = []
    def shape(glyphs, size:, text:)
      @calls << text
      glyphs
    end
  end

  def setup
    @font = Font.new
    @typesetter = Zaniah::TextSystem::Typesetter.new(font: @font, font_db: Database.new(@font), shaper: LegacyShaper.new)
  end

  def test_legacy_shaper_accepts_rtl_without_new_keywords
    line = @typesetter.layout_line("שלום", size: 1)
    assert_equal %w[ם ו ל ש], line.glyphs.map { |glyph| line.text.byteslice(glyph.start...glyph.finish) }
    assert_equal [4.0, 3.0, 2.0, 1.0, 0.0], line.carets.map(&:last)
    assert_equal [8, :upstream], line.hit_test(0)
    assert_equal [0, :downstream], line.hit_test(4)
    assert_equal [Zaniah::Bounds.new(2, 0, 2, 1)], line.selection_rects(0...4)
  end

  def test_mixed_runs_have_disjoint_selection_and_visual_arrow_keys
    line = @typesetter.layout_line("ab שלום cd", size: 1)
    assert_equal ["a", "b", " ", "ם", "ו", "ל", "ש", " ", "c", "d"],
      line.glyphs.map { |glyph| line.text.byteslice(glyph.start...glyph.finish) }
    assert_equal 2, line.selection_rects(1...5).length

    text = Zaniah::Text.new("שלום")
    text.instance_variable_set(:@line, @typesetter.layout_line("שלום", size: 1))
    assert_equal 2, text.send(:move_caret, 0, -1)
    logical = Zaniah::Text.new("שלום", caret_movement: :logical)
    logical.instance_variable_set(:@line, text.instance_variable_get(:@line))
    assert_equal 0, logical.send(:move_caret, 0, -1)
  end

  def test_paragraph_start_and_end_follow_base_direction
    start = @typesetter.layout_paragraph("שלום", width: 10, size: 1, align: :start)
    ending = @typesetter.layout_paragraph("שלום", width: 10, size: 1, align: :end)
    assert_equal :rtl, start.direction
    assert_equal 6, start.lines.first.x
    assert_equal 0, ending.lines.first.x
    assert_equal [8, :upstream], start.hit_test_with_affinity(Zaniah::Point.new(6, 0))
  end

  def test_mirroring_keeps_original_byte_offsets
    line = @typesetter.layout_line("א(", size: 1)
    bracket = line.glyphs.find { |glyph| glyph.start == 2 }
    assert_equal ")".ord, bracket.id
    assert_equal 3, bracket.finish
  end

  def test_headless_paragraph_keeps_rtl_hit_testing_and_selection
    paragraph = Zaniah::TextSystem::Paragraph.new("שלום", width: 10, size: 1, typesetter: nil)
    assert_equal :rtl, paragraph.direction
    assert_equal [8, :upstream], paragraph.hit_test_with_affinity(Zaniah::Point.new(7.6, 0))
    assert_in_delta 2.4, paragraph.selection_rects(0...8).sum(&:width), 0.001
    assert_in_delta 2.4, paragraph.offset_to_point(0).x - paragraph.lines.first.x, 0.001
  end

  def test_letter_spacing_preserves_visual_caret_order
    paragraph = @typesetter.layout_paragraph("שלום", width: 12, size: 1,
      letter_spacing: 0.5)
    line = paragraph.lines.first.layout
    assert_in_delta 6.0, line.width, 0.001
    assert line.visual_carets
    assert_equal [8, :upstream], line.hit_test(0)
    assert_equal [0, :downstream], line.hit_test(line.width)
  end
end
