# frozen_string_literal: true

module Zaniah
  module Input
    MouseDown = Data.define(:position, :button, :modifiers, :click_count)
  end
end
