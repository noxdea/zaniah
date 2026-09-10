# frozen_string_literal: true

module Zaniah
  module Platform
    module TUI
      # Terminal cells have fixed metrics; no font loading or rasterization.
      class TextRenderer
        attr_reader :runs
        attr_accessor :scale_factor
        def initialize
          @cache, @runs = {}, []
        end
        def start_frame = @runs.clear
        def end_frame; end
        def close; end
        def layout_line(text, font: nil, size: 14)
          @cache.shift if @cache.length >= 2000
          @cache[text] ||= begin
            value, byte, width, carets = text.dup.freeze, 0, 0.0, [[0, 0.0]]
            value.each_grapheme_cluster do |character|
              byte += character.bytesize
              width += Unicode.width(character) * 8
              carets << [byte, width]
            end
            TextSystem::LineLayout.new(value, [].freeze, width, 14, 6, size, carets.freeze)
          end
        end
        def paint_line(scene, line, x:, y:, color: "#ddd", spans: nil)
          cursor = 0
          spans.to_a.each do |first, last, tint|
            @runs << [x + line.x_for_index(cursor), y - line.ascent, line.text.byteslice(cursor...first), color, scene.current_clip] if first > cursor
            @runs << [x + line.x_for_index(first), y - line.ascent, line.text.byteslice(first...last), tint, scene.current_clip]
            cursor = last
          end
          @runs << [x + line.x_for_index(cursor), y - line.ascent, line.text.byteslice(cursor..), color, scene.current_clip] if cursor < line.text.bytesize
        end
      end
    end
  end
end
