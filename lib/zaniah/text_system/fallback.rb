# frozen_string_literal: true

module Zaniah
  module TextSystem
    module Fallback
      CJK = /noto.*cjk|hiragino|yu gothic|meiryo|pingfang|source han/i
      EMOJI = /emoji/i
      SYMBOL = /symbol|dingbat/i

      def self.rank(face, codepoint)
        names = face.families.join(" ")
        preferred = if emoji?(codepoint) then EMOJI
        elsif symbol?(codepoint) then SYMBOL
        elsif cjk?(codepoint) then CJK
        end
        preferred && names.match?(preferred) ? 0 : 1
      end

      def self.cjk?(codepoint) = (0x3000..0x30ff).cover?(codepoint) || (0x3400..0x9fff).cover?(codepoint) || (0xac00..0xd7af).cover?(codepoint)
      def self.emoji?(codepoint) = (0x1f000..0x1faff).cover?(codepoint) || (0x2600..0x27bf).cover?(codepoint)
      def self.symbol?(codepoint) = (0x2000..0x2bff).cover?(codepoint)
    end
  end
end
