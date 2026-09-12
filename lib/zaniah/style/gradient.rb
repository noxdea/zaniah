# frozen_string_literal: true

module Zaniah
  Gradient = Data.define(:kind, :stops, :angle, :center, :radius) do
    class << self
      def linear(angle: 90, stops:) = new(:linear, normalize(stops), angle.to_f, nil, nil)
      def radial(center: [0.5, 0.5], radius: 0.5, stops:) = new(:radial, normalize(stops), nil, center.map(&:to_f).freeze, radius.to_f)
      def conic(angle: 0, center: [0.5, 0.5], stops:) = new(:conic, normalize(stops), angle.to_f, center.map(&:to_f).freeze, nil)

      private

      def normalize(stops)
        raise ArgumentError, "a gradient needs at least two stops" unless stops.is_a?(Array) && stops.length >= 2
        result = stops.map do |position, color|
          raise ArgumentError, "gradient positions must be between 0 and 1" unless position.is_a?(Numeric) && position.between?(0, 1)
          [position.to_f, Color.parse(color)].freeze
        end
        raise ArgumentError, "gradient positions must be ordered" unless result.each_cons(2).all? { |left, right| left.first <= right.first }
        result.freeze
      end
    end
  end
end
