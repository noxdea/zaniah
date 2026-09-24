# frozen_string_literal: true

module Zaniah
  module UI
    class DockLayout
      Tabs = Data.define(:id, :panels, :active)
      Split = Data.define(:id, :orientation, :ratio, :first, :second)

      attr_reader :root

      def self.tabs(id:, panels:, active: nil)
        from_h({type: "tabs", id: id, panels: panels, active: active || Array(panels).first})
      end

      def self.split(id:, orientation:, ratio:, first:, second:)
        from_h({type: "split", id: id, orientation: orientation, ratio: ratio,
          first: first.is_a?(DockLayout) ? first.to_h : first,
          second: second.is_a?(DockLayout) ? second.to_h : second})
      end

      def self.from_h(value)
        new(parse(value))
      end

      def self.parse(value, depth = 0)
        raise ArgumentError, "dock layout must be a hash" unless value.is_a?(Hash)
        raise ArgumentError, "dock layout is too deep" if depth > 64
        field = ->(key) { value.key?(key) ? value[key] : value[key.to_s] }
        id = identifier(field.call(:id))
        case field.call(:type).to_s
        when "tabs"
          panels = Array(field.call(:panels)).map { |panel| identifier(panel) }
          raise ArgumentError, "tab group must contain panels" if panels.empty?
          raise ArgumentError, "panel IDs must be unique" unless panels.uniq == panels
          active = identifier(field.call(:active) || panels.first)
          raise ArgumentError, "active panel must belong to its tab group" unless panels.include?(active)
          Tabs.new(id: id, panels: panels.freeze, active: active)
        when "split"
          orientation = field.call(:orientation)&.to_sym
          raise ArgumentError, "dock split orientation must be horizontal or vertical" unless %i[horizontal vertical].include?(orientation)
          ratio = Float(field.call(:ratio))
          raise ArgumentError, "dock split ratio must be between zero and one" unless ratio.finite? && ratio > 0 && ratio < 1
          Split.new(id: id, orientation: orientation, ratio: ratio,
            first: parse(field.call(:first), depth + 1), second: parse(field.call(:second), depth + 1))
        else
          raise ArgumentError, "unknown dock layout node"
        end
      rescue TypeError
        raise ArgumentError, "dock split ratio must be numeric"
      end
      private_class_method :parse

      def self.identifier(value)
        raise ArgumentError, "dock IDs must be nonempty strings or symbols" unless value.is_a?(String) || value.is_a?(Symbol)
        text = value.to_s
        raise ArgumentError, "dock IDs must be nonempty" if text.empty?
        text.freeze
      end
      private_class_method :identifier

      def initialize(root)
        raise ArgumentError, "dock root must be tabs or split" unless root.is_a?(Tabs) || root.is_a?(Split)
        ids, panels = [], []
        walk(root) do |node|
          ids << node.id
          panels.concat(node.panels) if node.is_a?(Tabs)
        end
        raise ArgumentError, "dock node IDs must be unique" unless ids.uniq == ids
        raise ArgumentError, "dock panel IDs must be unique" unless panels.uniq == panels
        @root = root
        freeze
      end

      def to_h(node = @root)
        if node.is_a?(Tabs)
          {"type" => "tabs", "id" => node.id, "panels" => node.panels.dup, "active" => node.active}
        else
          {"type" => "split", "id" => node.id, "orientation" => node.orientation.to_s,
            "ratio" => node.ratio, "first" => to_h(node.first), "second" => to_h(node.second)}
        end
      end

      def groups
        result = []
        walk(@root) { |node| result << node if node.is_a?(Tabs) }
        result.freeze
      end

      def find_group(id) = groups.find { |group| group.id == id.to_s }
      def find_panel(id) = groups.find { |group| group.panels.include?(id.to_s) }

      private

      def walk(node, &block)
        yield node
        return if node.is_a?(Tabs)
        walk(node.first, &block)
        walk(node.second, &block)
      end
    end
  end
end
