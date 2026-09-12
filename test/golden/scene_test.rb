# frozen_string_literal: true

require_relative "../test_helper"

class GoldenSceneTest < Zaniah::UITest
  def test_modern_primitives
    assert_golden("scene/modern-primitives") do
      Zaniah::Canvas.new do |_bounds, cx|
        cx.scene.quad(20, 20, 160, 80,
          color: Zaniah::Gradient.linear(angle: 25, stops: [[0, "#0ea5e9"], [1, "#8b5cf6"]]),
          radius: Zaniah::Corners.new(20, 4, 20, 4),
          border_width: Zaniah::Edges.new(4, 2, 6, 1), border_color: "#f8fafc")
        cx.scene.quad(210, 20, 100, 100,
          color: Zaniah::Gradient.radial(stops: [[0, "#fef08a"], [1, "#f97316"]]), opacity: 0.85)
        cx.scene.shadow(360, 35, 120, 60, color: "#000a", blur: 12, spread: 2, radius: 12)
        cx.scene.push_transform(Zaniah::Transform.translate(380, 35).rotate(8)) do
          cx.scene.quad(0, 0, 120, 60, color: "#22c55e", radius: 12,
            border_width: 3, border_color: "#dcfce7", border_style: :dashed)
        end
      end
    end
  end
end
