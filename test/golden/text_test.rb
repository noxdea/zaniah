# frozen_string_literal: true

require_relative "../test_helper"

class GoldenTextTest < Zaniah::UITest
  class CellTypesetter
    def layout_line(text, font: nil, size: 1)
      byte, carets = 0, [[0, 0.0]]
      text.grapheme_clusters.each do |cluster|
        byte += cluster.bytesize
        carets << [byte, carets.length * 14.0]
      end
      Zaniah::TextSystem::LineLayout.new(text, [], carets.last.last, 16, 4, size, carets)
    end
  end

  def test_japanese_wrapping_and_kinsoku
    assert_golden("text/japanese-kinsoku") do
      push = paragraph("これは、日本語の禁則処理を確認する文章です。括弧（テスト）も折り返します。", :push)
      hanging = paragraph("ぶら下げでは、句読点。を行頭に残しません……長音——も分離しません。", :hanging)
      Zaniah::Canvas.new do |_bounds, cx|
        draw_paragraph(cx.scene, push, 24, 24, "#202936")
        draw_paragraph(cx.scene, hanging, 308, 24, "#29364a")
      end
    end
  end

  private

  def paragraph(text, mode)
    Zaniah::TextSystem::Paragraph.new(text, width: 252, size: 1, line_height: 24,
      kinsoku: mode, typesetter: CellTypesetter.new)
  end

  def draw_paragraph(scene, paragraph, x, y, background)
    scene.quad(x, y, 260, 160, color: background, radius: 8)
    paragraph.lines.each do |line|
      cursor = x + 8
      line.layout.text.grapheme_clusters.each do |cluster|
        color = Zaniah::TextSystem::Kinsoku::HEAD.include?(cluster) ? "#38bdf8" :
          Zaniah::TextSystem::Kinsoku::TAIL.include?(cluster) ? "#fb7185" : "#cbd5e1"
        scene.quad(cursor, y + 8 + line.y, 10, 16, color: color, radius: 2)
        cursor += 14
      end
    end
  end
end
