# frozen_string_literal: true

require_relative "arabic_joining_data"

module Zaniah::Unicode::ArabicJoining
  module_function

  # Unicode Joining_Type uses U for code points absent from the derived table.
  def type(codepoint)
    ranges = Zaniah::Unicode::ArabicJoiningData::RANGES
    index = (0...ranges.length).bsearch { |i| ranges[i][1] >= codepoint }
    index && ranges[index][0] <= codepoint ? ranges[index][2] : "U"
  end

  # Byte offsets match Glyph#start. Transparent marks do not interrupt joining.
  # A join-causing code point participates in context but has no form of its own.
  def forms(text)
    significant = []
    offset = 0
    text.each_char do |character|
      kind = type(character.ord)
      significant << [offset, kind] unless kind == "T"
      offset += character.bytesize
    end
    significant.each_with_index.each_with_object({}) do |((byte, kind), index), result|
      next unless %w[D R L].include?(kind)
      previous = index.positive? ? significant[index - 1][1] : "U"
      following = index + 1 < significant.length ? significant[index + 1][1] : "U"
      joins_previous = %w[D L C].include?(previous) && %w[D R C].include?(kind)
      joins_following = %w[D L C].include?(kind) && %w[D R C].include?(following)
      result[byte] = if joins_previous
        joins_following ? "medi" : "fina"
      else
        joins_following ? "init" : "isol"
      end
    end
  end
end
