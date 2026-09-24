# frozen_string_literal: true

module Zaniah
  module Input
    DataDrop = Data.define(:content, :position, :operation)

    class DragOver
      OPERATIONS = %i[copy move link none].freeze
      attr_reader :types, :position, :operations, :operation

      def initialize(types:, position:, operations: [:copy])
        raise TypeError, "drag types must be an Array of MIME names" unless types.is_a?(Array) && types.all? { |type| type.is_a?(String) }
        raise TypeError, "drag position must be a Point" unless position.is_a?(Point)
        raise ArgumentError, "invalid drag operations" unless operations.is_a?(Array) && operations.all? { |operation| OPERATIONS.include?(operation) && operation != :none }
        @types, @position, @operations, @operation = types.uniq.freeze, position, operations.uniq.freeze, :none
      end

      def accepts?(type) = @types.include?(type)
      def operation=(value)
        raise ArgumentError, "unsupported drag operation #{value.inspect}" unless value == :none || @operations.include?(value)
        @operation = value
      end
    end
  end
end
