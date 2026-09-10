# frozen_string_literal: true

module Zaniah
  class View
    include LengthUnits

    def div = Div.new
    def text(value, **options) = Text.new(value, **options)
    def list(**options, &render_item) = List.new(**options, &render_item)
    def svg(source, **options) = SVG.new(source, **options)
    def render(_cx) = raise NotImplementedError, "implement View#render"
  end
end
