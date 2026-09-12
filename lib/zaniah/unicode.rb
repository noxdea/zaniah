# frozen_string_literal: true

module Zaniah
  module Unicode
    # Ruby's Unicode-aware regexp engine implements extended grapheme clusters.
    def self.grapheme_clusters(text) = text.grapheme_clusters

    def self.grapheme_boundaries(text)
      offset = 0
      [0] + text.grapheme_clusters.map { |cluster| offset += cluster.bytesize }
    end

    def self.grapheme_boundary?(text, offset) = grapheme_boundaries(text).include?(offset)

    def self.previous_boundary(text, offset)
      grapheme_boundaries(text).reverse.find { |boundary| boundary < offset } || 0
    end

    def self.next_boundary(text, offset)
      grapheme_boundaries(text).find { |boundary| boundary > offset } || text.bytesize
    end

    def self.word_range_at(text, offset)
      clusters, starts, byte = text.grapheme_clusters, [], 0
      clusters.each { |cluster| starts << byte; byte += cluster.bytesize }
      return 0...0 if clusters.empty?
      index = starts.bsearch_index { |start| start >= offset }
      index = index && starts[index] == offset ? index : (index || starts.length) - 1
      kind = word_kind(clusters[index])
      first = index
      first -= 1 while first.positive? && word_kind(clusters[first - 1]) == kind
      last = index + 1
      last += 1 while last < clusters.length && word_kind(clusters[last]) == kind
      starts[first]...(starts[last] || text.bytesize)
    end

    def self.width(text, ambiguous: 1)
      require "rbconfig"
      require "unicode/display_width"
      ::Unicode::DisplayWidth.of(text, ambiguous, emoji: :rgi)
    end

    def self.word_kind(cluster)
      case cluster
      when /\p{Hiragana}/ then :hiragana
      when /\p{Katakana}/ then :katakana
      when /\p{Han}/ then :han
      when /[\p{L}\p{N}_]/ then :word
      when /\s/ then :space
      else :punctuation
      end
    end
    private_class_method :word_kind
  end
end
