# frozen_string_literal: true

module Zaniah
  module Unicode
    # Ruby's Unicode-aware regexp engine implements extended grapheme clusters.
    def self.grapheme_clusters(text) = text.grapheme_clusters
    def self.width(text, ambiguous: 1)
      require "rbconfig"
      require "unicode/display_width"
      ::Unicode::DisplayWidth.of(text, ambiguous, emoji: :rgi)
    end
  end
end
