# frozen_string_literal: true

module Zaniah
  Color = Data.define(:r, :g, :b, :a) do
    def self.parse(value)
      return value if value.is_a?(self)
      return new(*value, *(value.length == 3 ? [1.0] : [])) if value.is_a?(Array)
      hex = value.to_s.delete_prefix("#")
      hex = hex.chars.map { |character| character * 2 }.join if [3, 4].include?(hex.length)
      raise ArgumentError, "expected #RGB, #RGBA, #RRGGBB or #RRGGBBAA" unless hex.match?(/\A[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?\z/)
      channels = hex.scan(/../).map { |channel| channel.to_i(16) / 255.0 }
      channels << 1.0 if channels.length == 3
      new(*channels)
    end

    def opacity(value) = Color.new(r, g, b, a * value)
    def premultiplied = [r * a, g * a, b * a, a]
    def to_a = [r, g, b, a]

    def mix(other, amount)
      Color.new(*to_a.zip(Color.parse(other).to_a).map { |x, y| x + (y - x) * amount })
    end

    def to_hsla
      max, min = [r, g, b].max, [r, g, b].min
      delta, lightness = max - min, (max + min) / 2.0
      return HSLA.new(0, 0, lightness, a) if delta.zero?
      hue = if max == r then ((g - b) / delta) % 6
      elsif max == g then (b - r) / delta + 2
      else (r - g) / delta + 4
      end
      HSLA.new(hue / 6.0, delta / (1 - (2 * lightness - 1).abs), lightness, a)
    end
  end
end
