# frozen_string_literal: true

module Zaniah
  module Accessibility
    NativeEntry = Data.define(:path, :node, :parent, :children, :runtime_id)

    class NativeTree
      include Enumerable

      attr_reader :root

      def initialize(root)
        @entries = {}
        @next_runtime_id = 1
        @root = build(root, nil, []) if root
      end

      def each(&block) = block ? @entries.each_value(&block) : enum_for(__method__)
      def [](path) = @entries[path]

      def bounds(entry)
        current = entry
        while current
          return current.node.bounds if current.node.bounds
          current = current.parent
        end
        Bounds.new(0, 0, 0, 0)
      end

      def hit(point)
        select { |entry| bounds(entry).contains?(point) }.max_by { |entry| entry.path.length }
      end

      def focused(window)
        bounds = window.dispatcher.focused&.bounds
        bounds && hit(Point.new(bounds.x + bounds.width / 2.0, bounds.y + bounds.height / 2.0))
      end

      private

      def build(node, parent, path)
        entry = NativeEntry.new(path: path.freeze, node: node, parent: parent, children: [], runtime_id: next_runtime_id)
        @entries[entry.path] = entry
        children = node.children.map.with_index { |child, index| build(child, entry, path + [index]) }.freeze
        entry.children.replace(children)
        entry.children.freeze
        entry
      end

      def next_runtime_id = (@next_runtime_id += 1) - 1
    end
  end
end
