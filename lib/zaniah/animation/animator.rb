# frozen_string_literal: true

module Zaniah
  class Animation
    attr_reader :key, :from, :to, :started_at, :duration, :easing

    def initialize(key, from:, to:, started_at:, duration:, easing:, on_complete: nil)
      @key, @from, @to, @started_at = key, from, to, started_at
      @duration, @easing, @on_complete = duration, easing, on_complete
    end

    def sample(now)
      progress = duration.zero? ? 1.0 : ((now - started_at) / duration).clamp(0, 1)
      [Animation.interpolate(from, to, easing.call(progress)), progress >= 1]
    end

    def complete = @on_complete&.call

    def self.interpolatable?(from, to)
      (from.is_a?(Numeric) && to.is_a?(Numeric)) ||
        (from.is_a?(Color) && to.is_a?(Color)) ||
        (from.is_a?(Length) && to.is_a?(Length) && from.unit == to.unit) ||
        (from.is_a?(Transform) && to.is_a?(Transform))
    end

    def self.interpolate(from, to, progress)
      return from + (to - from) * progress if from.is_a?(Numeric) && to.is_a?(Numeric)
      return Color.new(*from.to_a.zip(to.to_a).map { |left, right| left + (right - left) * progress }) if from.is_a?(Color) && to.is_a?(Color)
      return Length.new(from.value + (to.value - from.value) * progress, from.unit) if from.is_a?(Length) && to.is_a?(Length) && from.unit == to.unit
      return Transform.new(*from.to_a.zip(to.to_a).map { |left, right| left + (right - left) * progress }) if from.is_a?(Transform) && to.is_a?(Transform)
      progress >= 1 ? to : from
    end
  end

  class Animator
    attr_reader :reduced_motion

    def initialize(clock:, reduced_motion: false)
      @clock, @reduced_motion = clock, reduced_motion
      @animations, @values = {}, {}
    end

    def reduced_motion=(value)
      @reduced_motion = !!value
      @animations.keys.each { |key| finish(key) } if @reduced_motion
      @reduced_motion
    end

    def animate(key, from:, to:, duration:, easing: :linear, &on_complete)
      duration = Float(duration)
      raise ArgumentError, "duration must be finite and nonnegative" unless duration.finite? && duration >= 0
      duration = 0.0 if reduced_motion
      animation = Animation.new(key, from: from, to: to, started_at: @clock.call,
        duration: duration, easing: Easing.resolve(easing), on_complete: on_complete)
      @values[key] = from
      if duration.zero?
        @values[key] = to
        animation.complete
      else
        @animations[key] = animation
      end
      animation
    end

    def spring(key, to:, stiffness: 170, damping: 26, mass: 1, from: value(key, 0), &on_complete)
      easing = Easing.spring(stiffness: stiffness, damping: damping, mass: mass)
      animate(key, from: from, to: to, duration: easing.settling_duration, easing: easing, &on_complete)
    end

    def sample(now = @clock.call)
      @animations.dup.each do |key, animation|
        @values[key], finished = animation.sample(now)
        finish(key) if finished
      end
      @values.dup.freeze
    end

    def active? = !@animations.empty?
    def animating?(key) = @animations.key?(key)
    def value(key, fallback = nil) = @values.fetch(key, fallback)

    def cancel(key)
      @animations.delete(key)
      @values.delete(key)
    end

    def finish(key)
      animation = @animations.delete(key)
      return @values[key] unless animation
      @values[key] = animation.to
      animation.complete
      @values[key]
    end
  end
end
