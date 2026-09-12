# frozen_string_literal: true

module Zaniah
  Theme = Data.define(:name, :appearance, :colors, :spacing, :radii, :shadows, :typography, :motion) do
    Colors = Data.define(:background, :surface, :surface_hover, :surface_pressed,
      :border, :border_focus, :text, :text_muted, :text_inverse, :accent,
      :accent_hover, :accent_text, :success, :warning, :danger, :info,
      :overlay_scrim, :selection, :ring)
    Typography = Data.define(:font_sans, :font_mono, :size_xs, :size_sm, :size_md,
      :size_lg, :size_xl, :size_2xl, :weight_normal, :weight_medium,
      :weight_semibold, :weight_bold, :line_height_tight, :line_height_normal,
      :line_height_relaxed)
    Motion = Data.define(:duration_fast, :duration_base, :duration_slow,
      :easing_standard, :easing_decelerate, :easing_accelerate, :reduced) do
      def reduced? = reduced
    end

    class << self
      def dark = @dark ||= build(:dark, :dark, %w[#181b20 #202936 #29364a #345477 #6b7c93 #6ea8fe #edf2f7 #b7c2d0 #111827 #2563a8 #1f5592 #ffffff #4ade80 #fbbf24 #fb7185 #60a5fa #00000099 #345477 #6ea8fe])
      def light = @light ||= build(:light, :light, %w[#f8fafc #ffffff #f1f5f9 #e2e8f0 #64748b #1d4ed8 #0f172a #475569 #ffffff #1d4ed8 #1e40af #ffffff #15803d #a16207 #b91c1c #0369a1 #0f172a80 #bfdbfe #1d4ed8])
      def high_contrast = @high_contrast ||= build(:high_contrast, :dark, %w[#000000 #000000 #1a1a1a #333333 #ffffff #ffff00 #ffffff #ffffff #000000 #ffff00 #ffffff #000000 #00ff66 #ffff00 #ff5577 #00ffff #000000cc #0055ff #ffff00])
      def for(appearance) = appearance == :light ? light : dark

      private

      def build(name, appearance, colors)
        new(name, appearance, Colors.new(*colors.map { |color| Color.parse(color) }),
          {0 => 0, 1 => 4, 2 => 8, 3 => 12, 4 => 16, 5 => 20, 6 => 24, 8 => 32, 10 => 40, 12 => 48, 16 => 64}.freeze,
          {none: 0, sm: 4, md: 8, lg: 12, full: 9999}.freeze,
          {sm: Shadow.new(y: 1, blur: 2), md: Shadow.new(y: 4, blur: 8), lg: Shadow.new(y: 8, blur: 20)}.freeze,
          Typography.new("sans-serif", "monospace", 11, 13, 14, 16, 20, 24, 400, 500, 600, 700, 1.2, 1.5, 1.75),
          Motion.new(0.12, 0.18, 0.28, :ease_in_out, :ease_out, :ease_in, false))
      end
    end
  end
end
