# frozen_string_literal: true

module Zaniah
  Corners = Data.define(:top_left, :top_right, :bottom_right, :bottom_left) do
    def self.all(value) = new(value, value, value, value)
  end
end
