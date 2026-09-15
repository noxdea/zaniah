# frozen_string_literal: true

require_relative "test_helper"

class TextOverlayTest < Minitest::Test
  class CellTypesetter
    attr_reader :layouts

    def initialize = @layouts = []

    def layout_line(text, font: nil, size: 1)
      @layouts << text
      byte, carets = 0, [[0, 0.0]]
      text.grapheme_clusters.each do |cluster|
        byte += cluster.bytesize
        carets << [byte, carets.length.to_f]
      end
      Zaniah::TextSystem::LineLayout.new(text, [], carets.last.last, 1, 0, size, carets)
    end

    def paint_paragraph(*) = nil
    def close = nil
  end

  def test_inline_overlay_participates_in_wrapping_and_coordinate_conversion
    plain = paragraph("abcd", width: 3)
    assert_equal %w[abc d], plain.lines.map { |line| line.layout.text }

    overlay = Zaniah::TextSystem::Paragraph::InlineOverlay.new(:hint, 1, 2, 1, :after)
    value = paragraph("abcd", width: 3, inline_overlays: [overlay])
    assert_equal ["a", "bcd"], value.lines.map { |line| line.layout.text }
    assert_equal Zaniah::Point.new(1, 0), value.offset_to_point(1)
    assert_equal 1, value.hit_test(Zaniah::Point.new(2, 0.5))
    assert_equal [1, 0, 2, 1], value.inline_placements.map { |item| [item.x, item.y, item.width, item.height] }.first

    before = paragraph("abcd", width: 3,
      inline_overlays: [overlay.with(align: :before)])
    assert_equal ["a", "b", "cd"], before.lines.map { |line| line.layout.text }
    assert_equal Zaniah::Point.new(2, 1), before.offset_to_point(1)
  end

  def test_text_positions_inline_and_block_elements_and_keeps_them_out_of_selection
    system = CellTypesetter.new
    window = Zaniah::Platform::Headless::Window.new(width: 4, height: 30)
    window.text_system = system
    clicked = 0
    inline = Zaniah::Div.new.w(2).h(2).bg("#f00").on_click { clicked += 1 }
    block = Zaniah::Div.new.bg("#00f")
    text = Zaniah::Text.new("a\nb", size: 1, wrap: :anywhere, line_height: 4).selectable
      .inline_overlay(offset: 1, element: inline)
      .block_overlay(line: 1, element: block, position: :above, height: 3)

    window.draw { text }
    window.tick
    assert_equal Zaniah::Bounds.new(1, 1, 2, 2), inline.layout_node.bounds
    assert_equal Zaniah::Bounds.new(0, 4, 4, 3), block.layout_node.bounds
    assert_equal Zaniah::Point.new(0, 7), text.offset_to_point(2)

    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(2, 2), :left, [], 1))
    window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(2, 2), :left, []))
    assert_equal 1, clicked
    assert_equal Zaniah::TextSelection.new(0), text.selection

    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(2, 5), :left, [], 1))
    window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(2, 5), :left, []))
    assert_equal Zaniah::TextSelection.new(0), text.selection
  ensure
    window&.close
  end

  def test_only_the_changed_logical_row_is_relaid_out
    system = CellTypesetter.new
    window = Zaniah::Platform::Headless::Window.new(width: 10, height: 30)
    window.text_system = system
    first = Zaniah::Div.new.w(1).h(1)
    text = Zaniah::Text.new("aa\nbb\ncc", size: 1, wrap: :anywhere, line_height: 2)
      .inline_overlay(offset: 1, element: first)
    layout(text, window)

    system.layouts.clear
    second = Zaniah::Div.new.w(1).h(1)
    text.inline_overlay(offset: 4, element: second)
    layout(text, window)
    refute_empty system.layouts
    assert system.layouts.all? { |value| value.delete("b").empty? }, system.layouts.inspect

    system.layouts.clear
    text.remove_overlay(second)
    layout(text, window)
    refute_empty system.layouts
    assert system.layouts.all? { |value| value.delete("b").empty? }, system.layouts.inspect
  ensure
    window&.close
  end

  def test_overlay_arguments_are_validated
    text = Zaniah::Text.new("é")
    element = Zaniah::Div.new
    assert_raises(ArgumentError) { text.inline_overlay(offset: 1, element: element) }
    assert_raises(ArgumentError) { text.inline_overlay(offset: 2, element: element, align: :middle) }
    assert_raises(ArgumentError) { text.block_overlay(line: 1, element: element, height: 2) }
    assert_raises(ArgumentError) { text.block_overlay(line: 0, element: element, height: 0) }
  end

  def test_overlay_boundary_splits_shaping_clusters
    path = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)
    font = Alhena::Font.open(path)
    typesetter = Zaniah::TextSystem::Typesetter.new(font: font,
      font_db: Zaniah::TextSystem::FontDB.new(paths: []))
    overlay = Zaniah::TextSystem::Paragraph::InlineOverlay.new(:hint, 1, 2, 1, :after)
    value = Zaniah::TextSystem::Paragraph.new("fi", width: 20, size: 14,
      typesetter: typesetter, inline_overlays: [overlay])
    refute value.lines.first.layout.glyphs.any? { |glyph| glyph.start < 1 && glyph.finish > 1 }
  ensure
    typesetter&.close
  end

  private

  def paragraph(text, **options)
    Zaniah::TextSystem::Paragraph.new(text, size: 1, line_height: 1,
      wrap: :anywhere, typesetter: CellTypesetter.new, **options)
  end

  def layout(text, window)
    node = text.request_layout(Zaniah::FrameContext.new(window))
    Zaniah::Layout::Engine.new.compute(node, width: 10, height: 30)
  end
end
