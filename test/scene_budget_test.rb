# frozen_string_literal: true
require_relative "test_helper"
require "zaniah/gpu/instance_packing"

class SceneBudgetTest < Minitest::Test
  def test_layer_order_survives_clear_and_interleaving
    scene = Zaniah::Scene.new
    scene.layer(10) { scene.quad(10, 0, 1, 1, color: "#fff") }
    scene.quad(0, 0, 1, 1, color: "#fff")
    scene.layer(10) { scene.quad(11, 0, 1, 1, color: "#fff") }
    assert_equal [40, 0, 80], scene.each_command.map { |_, offset, _| offset }
    packed = Zaniah::GPU::InstancePacking.pack(scene).first.unpack("f*")
    assert_equal [0, 10, 11], packed.each_slice(Zaniah::GPU::InstancePacking::STRIDE).map(&:first)
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
    quad = data.first(40)
    assert_equal [1, 2, 3, 4, 1, 0, 0, 1], quad.first(8)
    assert_equal [5, 6, 7, 8], quad[12, 4]
    assert_equal [0, 1, 0, 1], quad[16, 4]
    assert_equal [9, 9, 9, 9], quad[20, 4]
    assert_equal [1, 0, 0, 1, 0, 0], quad[32, 6]
    assert_equal [0.25, 0.5, 0.75, 1], data[60, 4]
    triangle = data.last(40)
    assert_equal [1, 2, 3, 4, 0, 0, 1, 1], triangle.first(8)
    assert_equal [5, 6], triangle[12, 2]
    assert_equal 3, triangle[31]
    before = texture.revision
    texture.upload(0, 0, 1, 1, "\xff".b * 4)
    assert_equal before + 1, texture.revision
  end

  def test_quad_only_instance_packing_preserves_clip_batches
    scene = Zaniah::Scene.new
    scene.quad(0, 0, 1, 1, color: "#fff")
    clip = Zaniah::Bounds.new(1, 1, 2, 2)
    scene.clip(clip) do
      scene.quad(1, 0, 1, 1, color: "#fff")
      scene.quad(2, 0, 1, 1, color: "#fff")
    end
    bytes, batches = Zaniah::GPU::InstancePacking.pack(scene)
    assert_equal [1, 2], batches.map(&:last)
    assert_equal [nil, clip], batches.map { |batch| batch[0][2] }
    scene.quad(3, 0, 1, 1, color: "#fff")
    assert_equal 3 * Zaniah::Scene::SPRITE_INSTANCE_BYTES, bytes.bytesize
    bytes = Zaniah::GPU::InstancePacking.pack(scene).first
    quads = scene.quads
    assert_equal quads.pack("f*"), bytes
    quads[0] = 9
    assert_equal 9, Zaniah::GPU::InstancePacking.pack(scene).first.unpack1("f")
  end


  def test_opaque_quad_fast_path_respects_clip
    scene = Zaniah::Scene.new
    scene.clip(Zaniah::Bounds.new(1, 1, 2, 1)) { scene.quad(0, 0, 4, 3, color: "#f00") }
    pixels = Zaniah::GPU::Software.new(4, 3).render(scene)
    assert_equal [0, 0, 0, 0], pixels.byteslice(0, 4).bytes
    assert_equal [255, 0, 0, 255], pixels.byteslice((1 * 4 + 1) * 4, 4).bytes
    assert_equal [0, 0, 0, 0], pixels.byteslice((2 * 4 + 1) * 4, 4).bytes
  end
end
