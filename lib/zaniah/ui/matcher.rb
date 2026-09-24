# frozen_string_literal: true

module Zaniah
  module UI
    module Matcher
      Match = Data.define(:index, :score, :ranges)

      class Substring
        def match(query, labels)
          needle = query.to_s.downcase
          labels.each_with_index.filter_map do |label, index|
            label = label.to_s
            position = label.downcase.index(needle)
            next unless position
            ranges = needle.empty? ? [] : [byte_range(label, position, needle.length)]
            Match.new(index: index, score: 0.0, ranges: ranges)
          end
        end

        private

        def byte_range(label, position, length)
          offsets = []
          byte = 0
          label.grapheme_clusters.each do |cluster|
            cluster.downcase.length.times { offsets << (byte...(byte + cluster.bytesize)) }
            byte += cluster.bytesize
          end
          offsets[position].begin...offsets[position + length - 1].end
        end
      end

      class Session
        def initialize(labels, matcher)
          @labels, @matcher = labels, matcher
          @query, @results = nil, nil
        end

        def results(query)
          return @results if query == @query
          @results = if @results && query.start_with?(@query) && @matcher.respond_to?(:refine)
            @matcher.refine(@results, query)
          else
            @matcher.match(query, @labels)
          end
          @query = query.dup.freeze
          @results
        end
      end

      def self.segments(label, ranges)
        parts = []
        offset = 0
        label.grapheme_clusters.each do |cluster|
          last = offset + cluster.bytesize
          highlighted = ranges.any? { |range| range.begin < last && range.end > offset }
          if parts.last && parts.last[1] == highlighted
            parts.last[0] << cluster
          else
            parts << [cluster.dup, highlighted]
          end
          offset = last
        end
        parts
      end
    end

    class HighlightedButton < Button
      def initialize(label, ranges:, **options)
        super(label, **options)
        @ranges = ranges
      end

      def build(cx)
        @highlight_color = cx.theme.colors.accent
        super.gap(0)
      end

      private

      def button_content(style)
        [Div.new.flex_row.gap(0).children(Matcher.segments(@label, @ranges).map do |part, highlighted|
          Text.new(part, size: style[:font_size], color: highlighted ? @highlight_color : style[:foreground])
        end)]
      end
    end
  end
end
