# frozen_string_literal: true

module Zaniah
  module TextSystem
    LineLayout = Data.define(:text, :glyphs, :width, :ascent, :descent, :size, :carets, :visual_carets, :writing_mode) do
      def initialize(*values, **keywords)
        if keywords.any?
          values = self.class.members.map { |name| keywords.fetch(name, nil) }
        end
        raise ArgumentError, "expected seven to nine line layout members" unless (7..9).cover?(values.length)
        values << nil if values.length == 7
        values << :horizontal_tb if values.length == 8
        values[8] ||= :horizontal_tb
        raise ArgumentError, "writing mode must be horizontal_tb or vertical_rl" unless %i[horizontal_tb vertical_rl].include?(values.last)
        if Data == Struct
          super(*values)
        else
          super(**self.class.members.zip(values).to_h)
        end
        freeze
      end

      def index_for_x(x)
        return hit_test(x).first if visual_carets
        index = carets.bsearch_index { |_, position| position >= x }
        return text.bytesize unless index
        return carets.first.first if index.zero?
        previous, following = carets[index - 1], carets[index]
        x - previous.last <= following.last - x ? previous.first : following.first
      end

      def x_for_index(index)
        caret = carets.bsearch { |byte, _| byte >= index }
        caret ? caret.last : width
      end

      def caret_x(offset, affinity: :downstream)
        raise ArgumentError, "affinity must be upstream or downstream" unless %i[upstream downstream].include?(affinity)
        return x_for_index(offset) unless visual_carets
        found = visual_carets.find { |byte, side, _| byte == offset && side == affinity }
        found ||= visual_carets.find { |byte, _, _| byte == offset }
        found ? found.last : x_for_index(offset)
      end

      def hit_test(x)
        return [index_for_x(x), :downstream] unless visual_carets
        nearest = visual_carets.min_by { |_, _, position| (position - x).abs }
        [nearest[0], nearest[1]]
      end

      def selection_rects(range)
        return [] if range.begin >= range.end
        return [Bounds.new(x_for_index(range.begin), 0, x_for_index(range.end) - x_for_index(range.begin), ascent + descent)] unless visual_carets
        if glyphs.empty?
          spans = visual_carets.each_slice(2).filter_map do |left_caret, right_caret|
            next unless right_caret
            from, to = [left_caret[0], right_caret[0]].minmax
            next if to == from || range.end <= from || range.begin >= to
            first = ([range.begin, from].max - from).to_f / (to - from)
            last = ([range.end, to].min - from).to_f / (to - from)
            left, right = [left_caret[2], right_caret[2]].minmax
            if left_caret[0] > right_caret[0]
              [left + (right - left) * (1 - last), left + (right - left) * (1 - first)]
            else
              [left + (right - left) * first, left + (right - left) * last]
            end
          end
          return spans.map { |left, right| Bounds.new(left, 0, right - left, ascent + descent) }
        end
        spans = glyphs.filter_map do |glyph|
          overlap = [range.end, glyph.finish].min - [range.begin, glyph.start].max
          next unless overlap.positive? && glyph.advance.positive?
          first = ([range.begin, glyph.start].max - glyph.start).to_f / (glyph.finish - glyph.start)
          last = ([range.end, glyph.finish].min - glyph.start).to_f / (glyph.finish - glyph.start)
          left = glyph.x + glyph.advance * (x_for_index(glyph.start) > x_for_index(glyph.finish) ? 1 - last : first)
          [left, left + glyph.advance * (last - first)]
        end.sort_by(&:first)
        spans.each_with_object([]) do |(left, right), result|
          if result.last && left <= result.last[1] + 0.001
            result.last[1] = [result.last[1], right].max
          else
            result << [left, right]
          end
        end.map { |left, right| Bounds.new(left, 0, right - left, ascent + descent) }
      end
    end
  end
end
