# frozen_string_literal: true

module Zaniah
  module LengthUnits
    def px(value) = Length.new(value, :px)
    def rems(value) = Length.new(value, :rem)
    def percent(value) = Length.new(value, :percent)
  end
end
