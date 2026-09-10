# frozen_string_literal: true

module Zaniah
  Edges = Data.define(:top, :right, :bottom, :left) do
    def self.all(value) = new(value, value, value, value)
  end
end
