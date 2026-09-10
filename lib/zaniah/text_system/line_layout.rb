# frozen_string_literal: true

module Zaniah
  module TextSystem
    LineLayout = Data.define(:text, :glyphs, :width, :ascent, :descent, :size, :carets) do
      def index_for_x(x)
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
    end
  end
end
