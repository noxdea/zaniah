# frozen_string_literal: true

module Zaniah
  module LengthUnits
    def px(value) = Length.new(value, :px)
    def rems(value) = Length.new(value, :rem)
    def percent(value) = Length.new(value, :percent)
    def fr(value) = Length.new(value, :fr)
    def minmax(min, max) = MinMax.new(min, max)

    def repeat(count, track)
      raise ArgumentError, "repeat count must be a positive integer" unless count.is_a?(Integer) && count.positive?
      Array.new(count, track)
    end
  end
end
