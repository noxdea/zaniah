# frozen_string_literal: true

module Zaniah
  Length = Data.define(:value, :unit) do
    def resolve(available, rem: 16)
      case unit
      when :px then value
      when :percent then available * value / 100.0
      when :rem then rem * value
      else raise ArgumentError, "unknown length unit #{unit}"
      end
    end
  end
end
