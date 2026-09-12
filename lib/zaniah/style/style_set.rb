# frozen_string_literal: true

require "set"

module Zaniah
  class StyleBuilder
    attr_reader :properties

    def initialize(properties = {}) = @properties = properties
    def style(**properties) = (@properties.merge!(properties); self)
    def bg(color) = style(background: color)
    def border_color(color) = style(border_color: color)
    def rounded(radius) = style(corner_radii: radius)
    def opacity(value) = style(opacity: value)
    def ring(width, color = nil, offset = 0) = style(ring: Ring.new(width, color, offset))
  end

  class StyleSet
    ORDER = %i[selected hover active focus focus_visible disabled].freeze
    attr_reader :base, :states

    def initialize(base = Layout::Style.new)
      @base, @states = base, {}
    end

    def merge(**properties)
      @base = @base.merge(**properties)
      self
    end

    def on(state, **properties)
      raise ArgumentError, "unknown style state #{state}" unless ORDER.include?(state)
      @states[state] = (@states[state] || {}).merge(properties).freeze
      self
    end

    def resolve(flags)
      ORDER.reduce(@base) { |style, state| flags.include?(state) && @states[state] ? style.merge(**@states[state]) : style }
    end

    def interactive? = !@states.empty?
  end
end
