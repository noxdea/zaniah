# frozen_string_literal: true

module Zaniah
  module Platform
    module Appearance
      def appearance = :dark
      def reduced_motion? = false
      def on_appearance(&block) = @on_appearance = block
    end
  end
end
