# frozen_string_literal: true

module Zaniah
  Point = Data.define(:x, :y) do
    def +(other) = Point.new(x + other.x, y + other.y)
    def -(other) = Point.new(x - other.x, y - other.y)
  end
end
