# frozen_string_literal: true

module Zaniah
  Shadow = Data.define(:x, :y, :blur, :spread, :color, :inset) do
    class << self
      alias record_new new

      def new(x: 0, y: 0, blur: 0, spread: 0, color: "#0008", inset: false)
        record_new(x.to_f, y.to_f, blur.to_f, spread.to_f, Color.parse(color), !!inset)
      end
    end
  end
end
