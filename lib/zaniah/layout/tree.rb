# frozen_string_literal: true

module Zaniah
  module Layout
    class Tree
      attr_reader :nodes

      def initialize = @nodes = []
      def new_node(**options) = @nodes.push(Node.new(**options)).length - 1
      def add_child(parent, child) = @nodes.fetch(parent).add(@nodes.fetch(child))
      def set_style(id, **style) = @nodes.fetch(id).style = @nodes.fetch(id).style.merge(**style)
      def compute(id, width:, height:) = Engine.new.compute(@nodes.fetch(id), width: width, height: height)
      def bounds(id) = @nodes.fetch(id).bounds
    end
  end
end
