# frozen_string_literal: true

module Zaniah
  module TextSystem
    class LineBreaker
      # ponytail: simplified UAX #14; add property tables when unsupported scripts require them.
      def initialize(text, wrap: :word, kinsoku: :push)
        raise ArgumentError, "wrap must be none, word, or anywhere" unless %i[none word anywhere].include?(wrap)
        @text, @wrap, @kinsoku = text, wrap, kinsoku
      end

      def ranges(width, &measure)
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
        bytes, total = [0], 0
        clusters.each { |cluster| bytes << (total += cluster.bytesize) }
        ranges, first = [], 0
        while first < clusters.length
          fit, last_word, index = first, nil, first
          while index < clusters.length
            candidate = segment.byteslice(bytes[first]...bytes[index + 1])
            break if index > first && measure.call(candidate) > width
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
