# frozen_string_literal: true

module Zaniah
  module Input
    ScrollWheel = Data.define(:position, :delta, :phase, :modifiers)
  end
end
