# frozen_string_literal: true

module Zaniah
  module TextSystem
    module Kinsoku
      HEAD = "、。，．）」』】〕〉》｝］！？ゝゞーァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎ".chars.freeze
      TAIL = "（「『【〔〈《｛［".chars.freeze
      UNSPLIT = %w[… —].freeze

      def self.adjust(clusters, first, cut, mode)
        raise ArgumentError, "kinsoku must be hanging, push, or none" unless %i[hanging push none].include?(mode)
        return cut if mode == :none || cut >= clusters.length
        if HEAD.include?(clusters[cut])
          if mode == :hanging
            cut += 1 while cut < clusters.length && HEAD.include?(clusters[cut])
          else
            cut -= 1 if cut - first > 1
          end
        end
        cut -= 1 while cut - first > 1 && TAIL.include?(clusters[cut - 1])
        if cut < clusters.length && cut > first && clusters[cut] == clusters[cut - 1] && UNSPLIT.include?(clusters[cut])
          cut = mode == :hanging ? cut + 1 : cut - 1 if mode != :none
        end
        cut.clamp(first + 1, clusters.length)
      end
    end
  end
end
