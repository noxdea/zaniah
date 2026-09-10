# frozen_string_literal: true

module Zaniah
  module Layout
    class Node
      attr_reader :style, :children, :generation, :cache
      attr_accessor :bounds, :parent, :measure, :baseline

      def initialize(style: Style.new, children: [], measure: nil)
        @style = style.is_a?(Hash) ? Style.new(**style) : style
        @children, @generation, @cache, @measure = [], 0, {}, measure
        @bounds, @baseline = Bounds.new(0, 0, 0, 0), 0
        children.each { |child| add(child) }
      end

      def add(child)
        raise ArgumentError, "node already has a parent" if child.parent
        child.parent = self
        @children << child
        touch
        child
      end

      def style=(style)
        @style = style.is_a?(Hash) ? Style.new(**style) : style
        touch
      end

      def touch
        @generation += 1
        @cache.clear
        parent&.touch
      end
    end
  end
end
