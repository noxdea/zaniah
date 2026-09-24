# frozen_string_literal: true

module Zaniah
  WindowState = Data.define(:frame, :display_id, :maximized, :fullscreen) do
    def initialize(frame:, display_id:, maximized:, fullscreen:)
      raise ArgumentError, "frame must be a Bounds" unless frame.is_a?(Bounds)
      raise ArgumentError, "frame size must be nonnegative and finite" unless [frame.width, frame.height].all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }
      raise ArgumentError, "frame origin must be finite or both nil" unless [frame.x, frame.y].all?(&:nil?) || [frame.x, frame.y].all? { |value| value.is_a?(Numeric) && value.finite? }
      raise ArgumentError, "display_id must be a String, Integer, or nil" unless display_id.nil? || display_id.is_a?(String) || display_id.is_a?(Integer)
      raise ArgumentError, "state flags must be booleans" unless [maximized, fullscreen].all? { |value| value == true || value == false }

      if Data == Struct
        super(frame, display_id, maximized, fullscreen)
      else
        super(frame: frame, display_id: display_id, maximized: maximized, fullscreen: fullscreen)
      end
      freeze
    end

    def to_h
      {frame: {x: frame.x, y: frame.y, width: frame.width, height: frame.height},
       display_id: display_id, maximized: maximized, fullscreen: fullscreen}
    end

    def self.from_h(value)
      return value if value.is_a?(self)
      raise ArgumentError, "window state must be a Hash" unless value.is_a?(Hash)

      fetch = ->(hash, key) { hash.key?(key) ? hash.fetch(key) : hash.fetch(key.to_s) }
      frame = fetch.call(value, :frame)
      frame = Bounds.new(*%i[x y width height].map { |key| fetch.call(frame, key) }) if frame.is_a?(Hash)
      new(frame: frame, display_id: fetch.call(value, :display_id),
          maximized: fetch.call(value, :maximized), fullscreen: fetch.call(value, :fullscreen))
    end
  end
end
