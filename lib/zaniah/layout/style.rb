# frozen_string_literal: true

module Zaniah
  module Layout
    class Style
      DEFAULTS = {display: :flex, flex_direction: :column, flex_wrap: :nowrap,
        justify_content: :start, align_items: :stretch, align_self: :auto,
        flex_grow: 0, flex_shrink: 1, flex_basis: :auto, width: :auto, height: :auto,
        min_width: 0, min_height: 0, max_width: Float::INFINITY, max_height: Float::INFINITY,
        padding: 0, margin: 0, border: 0, gap: 0, position: :relative,
        overflow: :visible}.freeze

      def initialize(**properties) = @values = DEFAULTS.merge(properties).freeze
      def [](name) = @values[name]
      def merge(**properties) = Style.new(**@values.merge(properties))
      def to_h = @values
    end
  end
end
