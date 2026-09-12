# frozen_string_literal: true

require_relative "test_helper"

class ParagraphTest < Minitest::Test
  class MonoTypesetter
    def layout_line(text, font: nil, size: 1)
      byte, carets = 0, [[0, 0.0]]
      text.grapheme_clusters.each do |cluster|
        byte += cluster.bytesize
        carets << [byte, carets.length.to_f]
      end
      Zaniah::TextSystem::LineLayout.new(text, [], carets.last.last, 1, 0, size, carets)
    end
  end

  def paragraph(text, **options)
    Zaniah::TextSystem::Paragraph.new(text, size: 1, line_height: 1,
      typesetter: MonoTypesetter.new, **options)
  end

  def test_word_wrapping_hit_testing_spacing_and_alignment
    value = paragraph("one two", width: 4, wrap: :word)
    assert_equal ["one ", "two"], value.lines.map { |line| line.layout.text }
    assert_equal 2, value.height
    assert_equal 5, value.hit_test(Zaniah::Point.new(1, 1))
    assert_equal Zaniah::Point.new(1, 1), value.offset_to_point(5)

    spaced = paragraph("ab", width: 6, wrap: :none, letter_spacing: 1, align: :center)
    assert_equal 3, spaced.lines.first.layout.width
    assert_equal 1.5, spaced.lines.first.x
  end

  def test_japanese_kinsoku_push_hanging_and_unsplit_sequences
    pushed = paragraph("あい、", width: 2, kinsoku: :push)
    assert_equal ["あ", "い、"], pushed.lines.map { |line| line.layout.text }
    hanging = paragraph("あい、", width: 2, kinsoku: :hanging)
    assert_equal ["あい、"], hanging.lines.map { |line| line.layout.text }
    opening = paragraph("あ（い", width: 2, kinsoku: :push)
    assert_equal ["あ", "（い"], opening.lines.map { |line| line.layout.text }
    unsplit = paragraph("あ……い", width: 2, kinsoku: :push)
    refute unsplit.lines.any? { |line| line.layout.text == "…" }
  end

  def test_ellipsis_and_explicit_newlines
    value = paragraph("abcd", width: 3, wrap: :none, ellipsis: true)
    assert_equal "ab…", value.lines.first.layout.text
    lines = paragraph("a\n\nb", width: 10).lines
    assert_equal ["a", "", "b"], lines.map { |line| line.layout.text }
  end
end
