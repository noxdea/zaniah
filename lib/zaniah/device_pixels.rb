# frozen_string_literal: true

module Zaniah
  DevicePixels = Data.define(:value) do
    def logical(scale) = value / Float(scale)
  end
end
