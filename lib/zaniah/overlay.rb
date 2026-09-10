# frozen_string_literal: true

module Zaniah
  class Overlay < Div
    def initialize
      super
      style(position: :absolute, left: 0, right: 0, top: 0, bottom: 0)
    end
  end
end
