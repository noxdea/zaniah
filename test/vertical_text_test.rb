# frozen_string_literal: true

require_relative "test_helper"
require "alhena"

class VerticalTextTest < Minitest::Test
  class Cells
    def layout_line(text, font: nil, size: 1, writing_mode: :horizontal_tb)
      byte, carets = 0, [[0, 0.0]]
      text.grapheme_clusters.each do |cluster|
        byte += cluster.bytesize
        carets << [byte, carets.length.to_f]
      end
      Zaniah::TextSystem::LineLayout.new(text, [], carets.last.last, 1, 0, size, carets,
        nil, writing_mode)
    end
  end

  def paragraph(text, **options)
    Zaniah::TextSystem::Paragraph.new(text, width: 2, size: 1, line_height: 2,
      typesetter: Cells.new, writing_mode: :vertical_rl, **options)
  end

  def test_columns_run_right_to_left_and_carets_follow_vertical_axis
    result = paragraph("あいうえ", wrap: :anywhere)
    assert_equal ["あい", "うえ"], result.lines.map { |line| line.layout.text }
    assert_equal [2, 0], result.lines.map(&:x)
    assert_equal [0, 0], result.lines.map(&:y)
    assert_equal [4, 2], [result.width, result.height]
    assert_equal Zaniah::Point.new(2, 1), result.offset_to_point(3)
    assert_equal 3, result.hit_test(Zaniah::Point.new(3, 1))
    assert_equal 6, result.hit_test(Zaniah::Point.new(0, 0))
    assert_equal [Zaniah::Bounds.new(2, 0, 2, 1)], result.selection_rects(0...3)
  end

  def test_vertical_inline_overlay_keeps_physical_dimensions
    overlay = Zaniah::TextSystem::Paragraph::InlineOverlay.new(:badge, 3, 4, 1, :after)
    result = paragraph("あい", width: 10, wrap: :none, inline_overlays: [overlay])
    placement = result.inline_placements.first
    assert_equal [4, 1], [placement.width, placement.height]
    assert_equal 3, placement.offset
    assert_equal :vertical_rl, result.writing_mode
  end

  def test_invalid_modes_are_rejected
    assert_raises(ArgumentError) { paragraph("a", writing_mode: :sideways) }
    assert_raises(ArgumentError) { paragraph("a", text_orientation: :sideways) }
  end

  def test_line_breaker_preserves_atomic_ruby_parent
    breaker = Zaniah::TextSystem::LineBreaker.new("a漢字b", wrap: :anywhere,
      atomic_ranges: [1...7])
    ranges = breaker.ranges_with_offsets(2) { |text, _first, _finish| text.length }
    assert_equal ["a", "漢字", "b"], ranges.map { |range| "a漢字b".byteslice(range) }
  end

  def test_latin_glyph_rotates_in_mixed_mode_but_not_upright_mode
    font = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
    renderer = Zaniah::TextSystem::Renderer.new(font: font, font_db: Zaniah::TextSystem::FontDB.new(paths: []))
    line = renderer.layout_line("A", size: 18, writing_mode: :vertical_rl)
    mixed, upright = Zaniah::Scene.new, Zaniah::Scene.new
    renderer.paint_line(mixed, line, x: 3, y: 4)
    renderer.paint_line(upright, line, x: 3, y: 4, text_orientation: :upright)
    mixed.sprites
    upright.sprites
    assert_equal [0, 1, -1, 0], mixed.sprite_transform(0).to_a.first(4)
    assert_equal [1, 0, 0, 1], upright.sprite_transform(0).to_a.first(4)
    refute_equal mixed.sprite_batches.first.bytes, upright.sprite_batches.first.bytes
  ensure
    renderer&.close
  end

  def test_editable_text_reports_vertical_caret_and_ime_bounds
    text = Zaniah::Text.new("あいう", size: 12, wrap: :anywhere,
      writing_mode: :vertical_rl).h(24).editable
    window = Zaniah::Platform::Headless::Window.new(width: 60, height: 30)
    window.render(text)
    para = text.instance_variable_get(:@paragraph)
    assert_equal :vertical_rl, para.writing_mode
    text.selection = Zaniah::TextSelection.new(3)
    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(para.lines.first.x + 1, 8), :left, [], 1))
    window.render(text)
    assert window.ime_state
    assert_operator window.ime_state.width, :>, window.ime_state.height
    assert_equal para.offset_to_point(0).x, text.offset_to_point(0).x
    text.selection = Zaniah::TextSelection.new(0)
    text.send(:text_action, :line_down)
    assert_equal 3, text.selection.head
    text.send(:text_action, :move_left)
    assert_equal 6, text.selection.head
  ensure
    window&.close
  end
end
