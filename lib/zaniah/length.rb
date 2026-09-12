# frozen_string_literal: true

module Zaniah
  MinMax = Data.define(:min, :max)

  Length = Data.define(:value, :unit) do
    def resolve(available, rem: 16)
      case unit
      when :px then value
      when :percent then available * value / 100.0
      when :rem then rem * value
      when :fr then raise ArgumentError, "fr lengths are only valid in grid tracks"
      else raise ArgumentError, "unknown length unit #{unit}"
      end
    end
  end
end
