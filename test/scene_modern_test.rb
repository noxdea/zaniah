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

    angled = T::Scene.new.quad(0, 0, 20, 20,
      color: T::Gradient.linear(angle: 25, stops: [[0, "#000"], [1, "#fff"]]))
    pixels = T::GPU::Software.new(20, 20).render(angled)
    assert_operator pixel(pixels, 20, 19, 19).first, :>, pixel(pixels, 20, 0, 0).first
  end

  def test_multi_stop_and_conic_gradients_use_bounded_ramps
    scene = T::Scene.new
    gradient = T::Gradient.linear(angle: 0, stops: [[0, "#f00"], [0.5, "#0f0"], [1, "#00f"]])
    scene.quad(0, 0, 11, 1, color: gradient)
    assert_equal 4, scene.quads[24]
    assert_equal [256, 256], [scene.quad_texture(0).width, scene.quad_texture(0).height]
    pixels = T::GPU::Software.new(11, 1).render(scene)
    assert_operator pixel(pixels, 11, 0, 0)[0], :>, 200
    assert_operator pixel(pixels, 11, 5, 0)[1], :>, 200
    assert_operator pixel(pixels, 11, 10, 0)[2], :>, 200

    scene.clear
    scene.quad(0, 0, 11, 11, color: T::Gradient.conic(stops: [[0, "#f00"], [0.5, "#0f0"], [1, "#00f"]]))
    assert_equal 6, scene.quads[24]
    assert_equal 40 * 4, T::GPU::InstancePacking.pack(scene).first.bytesize
    pixels = T::GPU::Software.new(11, 11).render(scene)
    refute_equal pixel(pixels, 11, 9, 5), pixel(pixels, 11, 5, 9)
    assert_raises(ArgumentError) { T::Gradient.conic(center: [Float::INFINITY, 0.5], stops: [[0, "#000"], [1, "#fff"]]) }
  end

  def test_multistop_gradients_share_atlas_rows_and_bound_lru
    scene = T::Scene.new
    colors = 257.times.map do |index|
      T::Gradient.linear(stops: [[0, "#000"], [0.5, format("#%06x", index + 1)], [1, "#fff"]])
    end
    scene.quad(0, 0, 2, 2, color: colors[0])
    scene.quad(2, 0, 2, 2, color: T::Gradient.conic(stops: colors[1].stops))
    assert_same scene.quad_texture(0), scene.quad_texture(40)
    assert_equal [0, 1], [scene.quads[8], scene.quads[48]]
    assert_equal 6, scene.quads[64]
    assert_equal 1, T::GPU::InstancePacking.pack(scene).last.length
    colors.drop(2).each_with_index { |gradient, index| scene.quad(index, 4, 1, 1, color: gradient) }
    assert_equal 256, scene.instance_variable_get(:@gradient_ramps).length
    assert_equal 1, scene.instance_variable_get(:@gradient_overflow_atlases).length
    refute_same scene.quad_texture(0), scene.quad_texture(256 * 40)
    scene.clear
    scene.quad(0, 0, 2, 2, color: colors.last)
    refute scene.instance_variable_get(:@gradient_ramps).key?(colors.first)
    assert_equal 256, scene.instance_variable_get(:@gradient_ramps).length
  end

  def test_shadow_is_one_instance_with_analytic_coverage
    scene = T::Scene.new.shadow(8, 8, 8, 8, color: "#000", blur: 2, spread: 1, radius: 2)
    assert_equal 40, scene.quads.length
    assert_equal 4, scene.quads[31]
    assert_equal [1, 0], scene.quads[38, 2]
    pixels = T::GPU::Software.new(24, 24).render(scene)
    assert_operator pixel(pixels, 24, 4, 12)[3], :>, 0
    assert_operator pixel(pixels, 24, 8, 12)[3], :>, pixel(pixels, 24, 4, 12)[3]
    assert_equal 0, pixel(pixels, 24, 0, 0)[3]
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

  def test_nested_layers_do_not_fall_behind_their_parent
    scene = T::Scene.new
    scene.layer(10) do
      scene.quad(0, 0, 1, 1, color: "#f00")
      scene.layer(1) { scene.quad(0, 0, 1, 1, color: "#0f0") }
    end

    assert_equal [10, 10], scene.commands.each_slice(4).map { |command| command[2] }
  end

  def test_software_renders_transformed_triangle
    scene = T::Scene.new
    scene.push_transform(T::Transform.translate(2, 1)) do
      scene.triangle([0, 0, 8, 0, 4, 8], color: "#f0f")
    end

    pixels = T::GPU::Software.new(12, 12).render(scene)
    assert_equal [255, 0, 255, 255], pixel(pixels, 12, 6, 4)
    assert_equal [0, 0, 0, 0], pixel(pixels, 12, 0, 0)
  end

  private

  def pixel(data, width, x, y) = data.byteslice((y * width + x) * 4, 4).bytes
end
