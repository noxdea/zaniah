# frozen_string_literal: true

module Zaniah
  module Easing
    module_function

    def linear = ->(value) { value }
    def ease_in = cubic_bezier(0.42, 0, 1, 1)
    def ease_out = cubic_bezier(0, 0, 0.58, 1)
    def ease_in_out = cubic_bezier(0.42, 0, 0.58, 1)

    def resolve(value)
      return value if value.respond_to?(:call)
      public_send(value || :linear)
    rescue NoMethodError
      raise ArgumentError, "unknown easing #{value.inspect}"
    end

    def cubic_bezier(x1, y1, x2, y2)
      values = [x1, y1, x2, y2].map { |value| Float(value) }
      raise ArgumentError, "cubic-bezier x values must be between 0 and 1" unless values.values_at(0, 2).all? { |value| value.between?(0, 1) }
      x1, y1, x2, y2 = values
      lambda do |input|
        input = input.to_f.clamp(0, 1)
        low, high = 0.0, 1.0
        16.times do
          time = (low + high) / 2.0
          sample = bezier(time, x1, x2)
          sample < input ? low = time : high = time
        end
        bezier((low + high) / 2.0, y1, y2)
      end
    end

    def spring(stiffness: 170, damping: 26, mass: 1)
      Spring.new(stiffness: stiffness, damping: damping, mass: mass)
    end

    def bezier(time, first, second)
      inverse = 1 - time
      3 * inverse * inverse * time * first + 3 * inverse * time * time * second + time**3
    end
    private_class_method :bezier
  end
end
