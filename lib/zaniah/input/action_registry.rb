# frozen_string_literal: true

module Zaniah
  module Input
    Command = Data.define(:name, :title, :category, :enabled, :checked, :handler)

    class ActionRegistry
      def initialize = @actions = {}

      def register(name, description: nil, title: nil, category: nil, enabled: nil, checked: nil, &block)
        title ||= description || name
        @actions[name.to_s] = Command.new(name, title, category, enabled, checked, block)
        [title, block]
      end

      def command(name) = @actions[name.to_s]
      def call(name, *args) = @actions.fetch(name.to_s).handler.call(*args)
      def entries = @actions.transform_values(&:title).freeze
    end
  end
end
