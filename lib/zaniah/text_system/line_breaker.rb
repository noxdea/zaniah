# frozen_string_literal: true

module Zaniah
  module TextSystem
    class LineBreaker
      # ponytail: simplified UAX #14; add property tables when unsupported scripts require them.
      def initialize(text, wrap: :word, kinsoku: :push, atomic_ranges: [])
        raise ArgumentError, "wrap must be none, word, or anywhere" unless %i[none word anywhere].include?(wrap)
        raise ArgumentError, "atomic ranges must be nonoverlapping byte ranges" unless atomic_ranges.is_a?(Array) &&
          atomic_ranges.all? { |range| range.is_a?(Range) && range.exclude_end? && range.begin.is_a?(Integer) && range.end.is_a?(Integer) && range.begin >= 0 && range.end <= text.bytesize && range.end > range.begin }
        @atomic_ranges = atomic_ranges.sort_by(&:begin)
        raise ArgumentError, "atomic ranges overlap" if @atomic_ranges.each_cons(2).any? { |first, following| first.end > following.begin }
        @text, @wrap, @kinsoku = text, wrap, kinsoku
      end

      def ranges(width, &measure)
        ranges_with_offsets(width) { |value, _first, _finish| measure.call(value) }
      end

      def ranges_with_offsets(width, &measure)
        width = Float(width)
        raise ArgumentError, "width must be nonnegative" if width.nan? || width.negative?
        result, offset = [], 0
        segments = @text.empty? ? [""] : @text.split("\n", -1)
        segments.each do |segment|
          result.concat(segment_ranges(segment, offset, width, measure))
          offset += segment.bytesize + 1
        end
        result
      end

      private

      def segment_ranges(segment, base, width, measure)
        return [base...base] if segment.empty?
        return [base...(base + segment.bytesize)] if @wrap == :none || width.infinite?
        clusters = segment.grapheme_clusters
        if @atomic_ranges.any?
          raw_bytes, total = [0], 0
          clusters.each { |cluster| raw_bytes << (total += cluster.bytesize) }
          grouped, index = [], 0
          while index < clusters.length
            range = @atomic_ranges.find { |item| item.begin == base + raw_bytes[index] }
            if range
              ending = raw_bytes.index(range.end - base)
              raise ArgumentError, "atomic range must follow grapheme boundaries within one line" unless ending && ending > index
              grouped << clusters[index...ending].join
              index = ending
            else
              grouped << clusters[index]
              index += 1
            end
          end
          clusters = grouped
        end
        bytes, total = [0], 0
        clusters.each { |cluster| bytes << (total += cluster.bytesize) }
        ranges, first = [], 0
        while first < clusters.length
          fit, last_word, index = first, nil, first
          while index < clusters.length
            candidate = segment.byteslice(bytes[first]...bytes[index + 1])
            break if index > first && measure.call(candidate, base + bytes[first], base + bytes[index + 1]) > width
            fit = index + 1
            last_word = fit if break_after?(clusters[index])
            index += 1
          end
          fit = first + 1 if fit == first
          cut = fit == clusters.length ? fit : @wrap == :word && last_word && last_word > first ? last_word : fit
          cut = Kinsoku.adjust(clusters, first, cut, @kinsoku) if cut < clusters.length
          ranges << (base + bytes[first]...base + bytes[cut])
          first = cut
        end
        ranges
      end

      def break_after?(cluster) = cluster.match?(/\s|[-‐‑‒–—\/]|[\p{Han}\p{Hiragana}\p{Katakana}]/)
    end
  end
end
