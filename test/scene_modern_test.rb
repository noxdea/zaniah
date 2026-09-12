# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/gpu/instance_packing"

class SceneModernTest < Minitest::Test
  T = Zaniah

  def test_opacity_edges_corners_and_dashed_border
    scene = T::Scene.new
    scene.quad(0, 0, 8, 8, color: "#00f", opacity: 0.5, radius: T::Corners.new(2, 0, 0, 0),
      border_width: T::Edges.new(2, 1, 0, 0), border_color: "#f00", border_style: :dashed)
    pixels = T::GPU::Software.new(8, 8).render(scene)
    assert_equal [255, 0, 0], pixel(pixels, 8, 1, 0).first(3)
    assert_operator pixel(pixels, 8, 1, 0).last, :>, 110
    assert_equal [0, 0, 255, 128], pixel(pixels, 8, 4, 4)
    assert_equal 40 * 4, T::GPU::InstancePacking.pack(scene).first.bytesize
  end

  def test_linear_and_radial_gradients
    linear = T::Scene.new.quad(0, 0, 10, 1,
      color: T::Gradient.linear(angle: 0, stops: [[0, "#000"], [1, "#fff"]]))
    pixels = T::GPU::Software.new(10, 1).render(linear)
    assert_operator pixel(pixels, 10, 0, 0).first, :<, 30
    assert_operator pixel(pixels, 10, 9, 0).first, :>, 225

    radial = T::Scene.new.quad(0, 0, 9, 9,
      color: T::Gradient.radial(stops: [[0, "#fff"], [1, "#000"]]))
    pixels = T::GPU::Software.new(9, 9).render(radial)
    assert_operator pixel(pixels, 9, 4, 4).first, :>, pixel(pixels, 9, 0, 0).first
  end

  def test_transform_applies_to_rendering_and_hit_testing
    scene = T::Scene.new
    scene.push_transform(T::Transform.translate(5, 2)) { scene.quad(0, 0, 3, 3, color: "#0f0") }
    pixels = T::GPU::Software.new(10, 8).render(scene)
    assert_equal [0, 255, 0, 255], pixel(pixels, 10, 5, 2)
    assert_equal [0, 0, 0, 0], pixel(pixels, 10, 0, 0)

    clicked = false
    element = T::Div.new.w(3).h(3).style(transform: T::Transform.translate(5, 2)).on_click { clicked = true }
    window = T::Platform.open_window(width: 10, height: 8)
    window.render(T::Div.new.child(element))
    window.input(T::Input::MouseDown.new(T::Point.new(6, 3), :left, [], 1))
    assert clicked
  ensure
    window&.close
  end

  def test_z_index_shadows_and_path
    back = T::Div.new.w(4).h(4).bg("#f00").style(position: :absolute, z_index: 2,
      shadows: [T::Shadow.new(x: 1, y: 1, blur: 0, spread: 1, color: "#0f0")])
    front = T::Div.new.w(4).h(4).bg("#00f").style(position: :absolute, z_index: 1)
    window = T::Platform.open_window(width: 8, height: 8)
    window.render(T::Div.new.children([back, front]))
    assert_equal [255, 0, 0, 255], pixel(window.device.pixels, 8, 1, 1)

    scene = T::Scene.new.path("M1 1H6V6H1Z", fill: "#fff", stroke: "#f00", width: 1)
    pixels = T::GPU::Software.new(8, 8).render(scene)
    assert_operator pixel(pixels, 8, 3, 3).last, :>, 0

    inset = T::Scene.new.shadow(0, 0, 8, 8, color: "#000", blur: 0, spread: 2, inset: true)
    pixels = T::GPU::Software.new(8, 8).render(inset)
    assert_operator pixel(pixels, 8, 0, 0).last, :>, 0
    assert_equal 0, pixel(pixels, 8, 4, 4).last
  ensure
    window&.close
  end

  private

  def pixel(data, width, x, y) = data.byteslice((y * width + x) * 4, 4).bytes
end
