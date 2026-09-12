# frozen_string_literal: true

module Zaniah
  class Spring
    attr_reader :stiffness, :damping, :mass, :settling_duration

    def initialize(stiffness:, damping:, mass: 1)
      @stiffness, @damping, @mass = Float(stiffness), Float(damping), Float(mass)
      raise ArgumentError, "spring values must be finite and positive" unless [@stiffness, @damping, @mass].all? { |value| value.finite? && value.positive? }
      @settling_duration = [-Math.log(0.001) / slowest_decay, 10.0].min
    end

    def call(progress)
      time = progress.to_f.clamp(0, 1) * settling_duration
      ratio = damping / (2 * Math.sqrt(stiffness * mass))
      frequency = Math.sqrt(stiffness / mass)
      return 1 - Math.exp(-frequency * time) * (1 + frequency * time) if (ratio - 1).abs < 1e-6
      if ratio < 1
        damped = frequency * Math.sqrt(1 - ratio * ratio)
        1 - Math.exp(-ratio * frequency * time) * (Math.cos(damped * time) + ratio * frequency / damped * Math.sin(damped * time))
      else
        root = Math.sqrt(ratio * ratio - 1)
        first, second = -frequency * (ratio - root), -frequency * (ratio + root)
        1 - (second * Math.exp(first * time) - first * Math.exp(second * time)) / (second - first)
      end
    end

    private

    def slowest_decay
      ratio = damping / (2 * Math.sqrt(stiffness * mass))
      frequency = Math.sqrt(stiffness / mass)
      ratio <= 1 ? ratio * frequency : frequency * (ratio - Math.sqrt(ratio * ratio - 1))
    end
  end
end
