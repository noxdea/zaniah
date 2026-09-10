# frozen_string_literal: true

module Zaniah
  HSLA = Data.define(:h, :s, :l, :a) do
    def to_rgba
      chroma = (1 - (2 * l - 1).abs) * s
      phase = (h % 1.0) * 6
      x = chroma * (1 - (phase % 2 - 1).abs)
      values = [[chroma, x, 0], [x, chroma, 0], [0, chroma, x],
        [0, x, chroma], [x, 0, chroma], [chroma, 0, x]][phase.floor]
      Color.new(*values.map { |value| value + l - chroma / 2.0 }, a)
    end
  end
end
