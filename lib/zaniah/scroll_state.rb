# frozen_string_literal: true

module Zaniah
  class ScrollState
    attr_reader :offset, :content_size, :viewport_size, :axis

    def initialize(axis: :both)
      raise ArgumentError, "axis must be vertical, horizontal, or both" unless %i[vertical horizontal both].include?(axis)
      @axis, @offset = axis, Point.new(0.0, 0.0)
      @content_size = @viewport_size = Size.new(0.0, 0.0)
    end

    def update(content_size:, viewport_size:)
      @content_size, @viewport_size = size(content_size), size(viewport_size)
      clamp!
    end

    def offset=(value)
      point = value.is_a?(Point) ? value : axis == :horizontal ? Point.new(value, @offset.y) : Point.new(@offset.x, value)
      raise ArgumentError, "scroll offset must be finite" unless [point.x, point.y].all? { |number| number.is_a?(Numeric) && number.finite? }
      @offset = Point.new(axis == :vertical ? 0.0 : point.x.to_f, axis == :horizontal ? 0.0 : point.y.to_f)
      clamp!
    end

    def scroll_by(delta)
      delta = axis == :horizontal ? Point.new(delta, 0) : Point.new(0, delta) unless delta.is_a?(Point)
      self.offset = Point.new(@offset.x + delta.x, @offset.y + delta.y)
    end

    def scroll_to(position, animate: false)
      # ponytail: scrolling is immediate until M7 supplies the shared Animator.
      self.offset = position
    end

    def preserve_anchor(delta) = scroll_by(axis == :horizontal ? Point.new(delta, 0) : Point.new(0, delta))
    def at_top? = @offset.y <= 0
    def at_bottom? = @offset.y >= max_offset.y
    def at_left? = @offset.x <= 0
    def at_right? = @offset.x >= max_offset.x

    def max_offset
      Point.new([@content_size.width - @viewport_size.width, 0].max,
        [@content_size.height - @viewport_size.height, 0].max)
    end

    def clamp!
      maximum = max_offset
      @offset = Point.new(@offset.x.clamp(0, maximum.x), @offset.y.clamp(0, maximum.y))
    end

    def scroll_rect(bounds, align: :nearest)
      x = aligned_offset(@offset.x, @viewport_size.width, bounds.x, bounds.width, align)
      y = aligned_offset(@offset.y, @viewport_size.height, bounds.y, bounds.height, align)
      self.offset = Point.new(x, y)
    end

    private

    def size(value)
      value = Size.new(*value) if value.is_a?(Array)
      raise ArgumentError, "scroll sizes must be finite and nonnegative" unless value.is_a?(Size) && [value.width, value.height].all? { |number| number.is_a?(Numeric) && number.finite? && number >= 0 }
      Size.new(value.width.to_f, value.height.to_f)
    end

    def aligned_offset(current, viewport, start, length, align)
      case align
      when :start then start
      when :center then start - (viewport - length) / 2.0
      when :end then start + length - viewport
      when :nearest then start < current ? start : start + length > current + viewport ? start + length - viewport : current
      else raise ArgumentError, "unknown alignment #{align.inspect}"
      end
    end
  end
end
