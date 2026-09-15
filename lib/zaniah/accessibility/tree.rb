# frozen_string_literal: true

module Zaniah
  module Accessibility
    Change = Data.define(:kind, :path, :before, :after)
    Event = Data.define(:kind, :id, :path, :node)

    class Tree
      attr_reader :root, :changes, :events, :revision

      def initialize
        @root, @changes, @events, @revision = nil, [], [], 0
      end

      def update(renderable, context, overlays: [])
        @next_action_owners = {}
        nodes = [renderable, *overlays].filter_map { |item| semantic(item, context) }
        next_root = nodes.length == 1 ? nodes.first : nodes.empty? ? nil : Accessibility.node(role: :group, label: "Application", children: nodes)
        validate_ids(next_root) if next_root
        @changes = diff(@root, next_root).freeze
        @events = events_for(@changes).freeze
        if @changes.empty?
          @action_owners = previous_action_owners(@root, next_root)
          return false
        end
        @root = next_root
        @action_owners = @next_action_owners
        @revision += 1
        true
      end

      def each
        return enum_for(__method__) unless block_given?
        walk(@root) { |node, path| yield node, path } if @root
      end

      def find(&predicate) = each.find { |node, _path| predicate.call(node) }&.first

      def perform(node, action)
        owner = @action_owners&.[](node.object_id)
        owner&.accessibility_action(node, action)
      end

      def assign(node, value)
        owner = @action_owners&.[](node.object_id)
        owner&.accessibility_value(node, value) if owner&.respond_to?(:accessibility_value)
      end

      private

      def semantic(renderable, context)
        return unless renderable
        node = renderable.accessibility_node(context) if renderable.respond_to?(:accessibility_node)
        if node.is_a?(Node)
          register_actions(node, renderable) if renderable.respond_to?(:accessibility_action)
          return node
        end
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

        before_ids = indexed_ids(before.children)
        matched = {}
        pairs = after.children.map.with_index do |child, after_index|
          before_index = child.id.nil? ? after_index : before_ids[child.id]
          before_child = before.children[before_index] if before_index && !matched[before_index]
          before_child = nil if child.id.nil? && before_child && !before_child.id.nil?
          matched[before_index] = true if before_child
          [child, after_index, before_child, before_index]
        end
        before.children.each_with_index do |child, index|
          changes.concat(diff(child, nil, path + [index])) unless matched[index]
        end
        pairs.each do |child, after_index, before_child, before_index|
          unless before_child
            changes.concat(diff(nil, child, path + [after_index]))
            next
          end
          if !child.id.nil? && before_index != after_index
            changes << Change.new(kind: :moved, path: (path + [after_index]).freeze,
              before: before_child, after: child)
          end
          changes.concat(diff(before_child, child, path + [after_index]))
        end
        changes
      end

      def indexed_ids(children)
        children.each_with_index.each_with_object({}) do |(child, index), result|
          result[child.id] = index unless child.id.nil?
        end
      end

      def events_for(changes)
        changes.flat_map do |change|
          node = change.after || change.before
          path = change.path
          id = node.id.nil? ? path : node.id
          events = [Event.new(kind: {added: :structure, removed: :structure, updated: :property, moved: :layout}.fetch(change.kind),
            id: id, path: path, node: node)]
          special_nodes(change).each do |after, before, special_path|
            special_id = after.id.nil? ? special_path : after.id
            if after.states[:focused] && !before&.states&.[](:focused)
              events << Event.new(kind: :focus, id: special_id, path: special_path, node: after)
            end
            if after.states[:live] && live_changed?(change.with(path: special_path, before: before, after: after))
              events << Event.new(kind: :announcement, id: special_id, path: special_path, node: after)
            end
          end
          events
        end
      end

      def special_nodes(change)
        return [] unless change.after
        return [] if change.kind == :moved
        return [[change.after, change.before, change.path]] unless change.kind == :added && change.after
        nodes = []
        walk(change.after, change.path) { |node, path| nodes << [node, nil, path] }
        nodes
      end

      def live_changed?(change)
        !change.before || change.before.label != change.after.label || change.before.value != change.after.value ||
          change.before.states[:revision] != change.after.states[:revision]
      end

      def register_actions(node, owner)
        @next_action_owners[node.object_id] = owner unless node.actions.empty?
        node.children.each { |child| register_actions(child, owner) }
      end

      def validate_ids(node)
        ids = node.children.map(&:id).reject(&:nil?)
        raise ArgumentError, "accessibility ids must be unique among siblings" unless ids.uniq.length == ids.length
        node.children.each { |child| validate_ids(child) }
      end

      def previous_action_owners(before, after)
        owners = {}
        return owners unless before && after
        pending = [[before, after]]
        until pending.empty?
          previous, current = pending.pop
          owner = @next_action_owners[current.object_id]
          owners[previous.object_id] = owner if owner
          previous.children.zip(current.children) { |pair| pending << pair }
        end
        owners
      end

      def walk(node, path = [], &block)
        yield node, path.freeze
        node.children.each_with_index { |child, index| walk(child, path + [index], &block) }
      end
    end
  end
end
