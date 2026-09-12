# frozen_string_literal: true

module Zaniah
  module Layout
    class Style
      DEFAULTS = {display: :flex, flex_direction: :column, flex_wrap: :nowrap,
        justify_content: :start, align_items: :stretch, align_self: :auto,
        flex_grow: 0, flex_shrink: 1, flex_basis: :auto, width: :auto, height: :auto,
        min_width: 0, min_height: 0, max_width: Float::INFINITY, max_height: Float::INFINITY,
        padding: 0, margin: 0, border: 0, gap: 0, position: :relative,
        direction: :ltr, padding_start: nil, padding_end: nil,
        margin_start: nil, margin_end: nil, border_start: nil, border_end: nil,
        overflow: :visible, aspect_ratio: nil, grid_template_columns: nil,
        grid_template_rows: nil, grid_column: nil, grid_row: nil, row_gap: nil,
        column_gap: nil, z_index: 0, opacity: 1.0, transform: nil,
        background: nil, border_widths: nil, border_style: :solid,
        border_color: nil, corner_radii: nil, shadows: nil, cursor: nil,
        ring: nil, text_color: nil, font_size: nil, font_family: nil,
        line_height: nil, letter_spacing: nil, text_align: :start,
        text_wrap: :wrap, text_overflow: :clip}.freeze
      INHERITED = %i[text_color font_size font_family line_height letter_spacing].freeze

      def initialize(**properties) = @values = DEFAULTS.merge(properties).freeze
      def [](name) = @values[name]
      def merge(**properties) = Style.new(**@values.merge(properties))
      def to_h = @values

      def inherit(parent)
        inherited = INHERITED.to_h { |name| [name, self[name] || parent[name]] }
        merge(**inherited)
      end
    end
  end
end
