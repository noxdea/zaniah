# frozen_string_literal: true

module Zaniah
  module Accessibility
    Change = Data.define(:kind, :path, :before, :after)

    class Tree
      attr_reader :root, :changes, :revision

      def initialize
        @root, @changes, @revision = nil, [], 0
      end

      def update(renderable, context, overlays: [])
        nodes = [renderable, *overlays].filter_map { |item| semantic(item, context) }
        next_root = nodes.length == 1 ? nodes.first : nodes.empty? ? nil : Accessibility.node(role: :group, label: "Application", children: nodes)
        @changes = diff(@root, next_root).freeze
        return false if @changes.empty?
        @root = next_root
        @revision += 1
        true
      end

      def each
        return enum_for(__method__) unless block_given?
        walk(@root) { |node, path| yield node, path } if @root
      end

      def find(&predicate) = each.find { |node, _path| predicate.call(node) }&.first

      private

      def semantic(renderable, context)
        return unless renderable
        node = renderable.accessibility_node(context) if renderable.respond_to?(:accessibility_node)
        return node if node.is_a?(Node)
        children = renderable.respond_to?(:children) ? renderable.children : []
        nodes = children.filter_map { |child| semantic(child, context) }
        Accessibility.node(role: :group, children: nodes) unless nodes.empty?
      end

      def diff(before, after, path = [])
        return [] if before == after
        return [Change.new(kind: before ? :removed : :added, path: path.freeze, before: before, after: after)] unless before && after
        changes = []
        if before.with(children: []) != after.with(children: [])
          changes << Change.new(kind: :updated, path: path.freeze, before: before, after: after)
        end
        [before.children.length, after.children.length].max.times do |index|
          changes.concat(diff(before.children[index], after.children[index], path + [index]))
        end
        changes
      end

      def walk(node, path = [], &block)
        yield node, path.freeze
        node.children.each_with_index { |child, index| walk(child, path + [index], &block) }
      end
    end
  end
end
