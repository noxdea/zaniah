# frozen_string_literal: true

module Zaniah
  class Anchored < Div
    def initialize(anchor:, offset: Point.new(0, 0))
      super()
      style(position: :absolute, left: anchor.x + offset.x, top: anchor.y + offset.y)
    end
  end
end
