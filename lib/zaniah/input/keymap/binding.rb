# frozen_string_literal: true

module Zaniah
  module Input
    class Keymap
      Binding = Data.define(:keys, :predicate, :action)
    end
  end
end
