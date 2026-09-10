# frozen_string_literal: true
require_relative "test_helper"
require "zaniah/gpu/instance_packing"

class SceneBudgetTest < Minitest::Test
  def test_layer_order_survives_clear_and_interleaving
    scene = Zaniah::Scene.new
    scene.layer(10) { scene.quad(10, 0, 1, 1, color: "#fff") }
    scene.quad(0, 0, 1, 1, color: "#fff")
    scene.layer(10) { scene.quad(11, 0, 1, 1, color: "#fff") }
    assert_equal [17, 0, 34], scene.each_command.map { |_, offset, _| offset }
    scene.clear
    scene.quad(0, 0, 1, 1, color: "#fff")
    assert_equal [0], scene.each_command.map { |_, offset, _| offset }
  end
  def test_instance_payloads_include_every_quad_sprite_and_triangle_field
    scene = Zaniah::Scene.new
    scene.quad(1, 2, 3, 4, color: "#f00", radius: [5, 6, 7, 8], border_width: 9, border_color: "#0f0")
    texture = Zaniah::GPU::Texture.new(8, 8)
    scene.sprite(1, 2, 3, 4, texture: texture, source: Zaniah::Bounds.new(2, 4, 6, 8))
    scene.triangle([1, 2, 3, 4, 5, 6], color: "#00f")
    data = Zaniah::GPU::InstancePacking.pack(scene).first.unpack("f*")
    assert_equal [1, 2, 3, 4, 1, 0, 0, 1, 5, 6, 7, 8, 0, 1, 0, 1, 9, 0, 0, 0, 0, 0, 0, 0], data.first(24)
    assert_equal [0.25, 0.5, 0.75, 1], data[44, 4]
    assert_equal [1, 2, 3, 4, 0, 0, 1, 1, 5, 6, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0], data.last(24)
    before = texture.revision
    texture.upload(0, 0, 1, 1, "\xff".b * 4)
    assert_equal before + 1, texture.revision
  end
end
