# frozen_string_literal: true

module Zaniah
  module Accessibility
    Node = Data.define(:role, :label, :value, :bounds, :states, :children, :actions) do
      def id = states[:accessibility_id]
    end

    def self.node(role:, id: nil, label: nil, value: nil, bounds: nil, states: {}, children: [], actions: [])
      states = states.merge(accessibility_id: id) unless id.nil?
      Node.new(role: role.to_sym, label: label&.to_s, value: value, bounds: bounds,
        states: states.dup.freeze, children: children.dup.freeze, actions: actions.map(&:to_sym).freeze)
    end
  end
end
