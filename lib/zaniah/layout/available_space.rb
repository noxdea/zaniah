# frozen_string_literal: true

module Zaniah
  module Layout
    AvailableSpace = Data.define(:kind, :value) do
      def self.definite(value) = new(:definite, value)
      def self.min_content = new(:min_content, nil)
      def self.max_content = new(:max_content, nil)
    end
  end
end
