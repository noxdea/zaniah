# frozen_string_literal: true

require_relative "../test_helper"

class BidiTextGoldenTest < Zaniah::UITest
  # The checked-in Latin font has no Hebrew glyphs. Fixed-width colored cells
  # keep this a cross-platform visual test of paragraph order and selection.
  class CellFont
    def units_per_em = 1
    def ascent = 1
    def descent = 0
    def glyph_id(point, variation_selector: nil) = point.is_a?(String) ? point.ord : point
    def advance(_id, size:) = 16.0
    def tables = {}
  end

  class CellFonts
    def initialize(font) = @font = font
    def find = @font
    def fallback(_point, _primary) = @font
  end

  %i[dark light high_contrast].each do |appearance|
    define_method("test_mixed_hebrew_english_#{appearance}") do
      assert_golden("text/bidi-mixed-#{appearance}", theme: appearance) do
        theme = @app.global(:theme)
        font = CellFont.new
        typesetter = Zaniah::TextSystem::Typesetter.new(font: font, font_db: CellFonts.new(font))
        rows = ["AB שלום 12", "שלום AB 12"].map do |value|
          typesetter.layout_paragraph(value, width: 300, size: 1, wrap: :none, line_height: 28)
        end
        Zaniah::Canvas.new do |_bounds, cx|
          scene = cx.scene
          scene.quad(0, 0, 800, 600, color: theme.colors.background)
          scene.quad(24, 24, 332, 96, color: theme.colors.surface, radius: 8)
          rows.each_with_index do |paragraph, row|
            origin_y = 34 + row * 40
            paragraph.selection_rects(3...7).each do |rect|
              scene.quad(36 + rect.x, origin_y + rect.y, rect.width, 22,
                color: theme.colors.selection, radius: 3)
            end
            paragraph.lines.each do |line|
              line.layout.glyphs.each do |glyph|
                scene.quad(36 + line.x + glyph.x + 2, origin_y + line.y + 2, 12, 18,
                  color: cell_color(glyph.id), radius: 2)
              end
            end
          end
        end
      end
    end
  end

  private

  def cell_color(codepoint)
    case codepoint
    when "ש".ord then "#ef4444"
    when "ל".ord then "#f97316"
    when "ו".ord then "#eab308"
    when "ם".ord then "#22c55e"
    when 0x30..0x39 then "#06b6d4"
    when 0x41..0x5A then "#a855f7"
    else "#64748b"
    end
  end
end
