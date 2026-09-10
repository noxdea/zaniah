# frozen_string_literal: true

module Zaniah
  module TextSystem
    Glyph = Data.define(:font, :id, :start, :finish, :x, :advance)
  end
end
