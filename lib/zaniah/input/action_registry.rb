# frozen_string_literal: true

module Zaniah
  module Input
    class ActionRegistry
      def initialize = @actions = {}
      def register(name, description: name, &block) = @actions[name.to_s] = [description, block]
      def call(name, *args) = @actions.fetch(name.to_s)[1].call(*args)
      def entries = @actions.transform_values(&:first).freeze
    end
  end
end
