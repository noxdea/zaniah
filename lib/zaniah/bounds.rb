# frozen_string_literal: true

module Zaniah
  Bounds = Data.define(:x, :y, :width, :height) do
    def right = x + width
    def bottom = y + height
    def contains?(point) = point.x >= x && point.y >= y && point.x < right && point.y < bottom

    def intersect(other)
      left, top = [x, other.x].max, [y, other.y].max
      Bounds.new(left, top, [[right, other.right].min - left, 0].max,
        [[bottom, other.bottom].min - top, 0].max)
    end

    def inset(edges)
      edges = Edges.all(edges) if edges.is_a?(Numeric)
      Bounds.new(x + edges.left, y + edges.top,
        [width - edges.left - edges.right, 0].max,
        [height - edges.top - edges.bottom, 0].max)
    end
  end
end
