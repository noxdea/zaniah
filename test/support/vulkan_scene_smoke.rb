# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "zaniah/data_compat"
require "zaniah/error"
require "zaniah/geometry"
require "zaniah/style/gradient"
require "zaniah/style/transform"
require "zaniah/gpu/texture"
require "zaniah/gpu/buffer"
require "zaniah/gpu/pipeline"
require "zaniah/gpu/frame_encoder"
require "zaniah/scene"
require "zaniah/gpu/software"
require "zaniah/gpu"
require "zaniah/gpu/vulkan"

scene = Zaniah::Scene.new
scene.quad(8, 8, 24, 20,
  color: Zaniah::Gradient.linear(angle: 0, stops: [[0, "#f00"], [1, "#00f"]]),
  radius: [5, 2, 5, 2], border_width: Zaniah::Edges.new(2, 3, 2, 3),
  border_color: "#fff", transform: Zaniah::Transform.translate(4, 0))
rgba = Zaniah::GPU::Texture.new(2, 2, data: [255, 0, 0, 255, 0, 255, 0, 255,
  0, 0, 255, 255, 255, 255, 0, 255].pack("C*"))
mono = Zaniah::GPU::Texture.new(2, 2, format: :r8, data: [0, 255, 255, 0].pack("C*"))
scene.sprite(40, 8, 8, 8, texture: rgba)
scene.sprite(52, 8, 8, 8, texture: mono, color: "#0f0")
scene.clip(Zaniah::Bounds.new(10, 34, 10, 20)) { scene.quad(0, 36, 30, 16, color: "#0ff") }
scene.triangle([40, 36, 60, 36, 50, 56], color: "#f0f")

software = Zaniah::GPU::Software.new(64, 64)
expected = software.render(scene, clear: "#111")
vulkan = Zaniah::GPU.create(backend: :vulkan, width: 64, height: 64)
begin
  raise "Vulkan retained initialization temporaries" unless vulkan.instance_variable_get(:@arena).empty?
  actual = vulkan.render(scene, clear: "#111")
  samples = [[20, 16], [40, 8], [41, 9], [46, 9], [53, 9], [58, 9],
    [9, 40], [12, 40], [22, 40], [50, 44]]
  mismatches = samples.filter_map do |x, y|
    offset = (y * 64 + x) * 4
    left, right = expected.byteslice(offset, 4).unpack("C4"), actual.byteslice(offset, 4).unpack("C4")
    "#{x},#{y}: #{right.inspect} != #{left.inspect}" unless left.zip(right).all? { |a, b| (a - b).abs <= 5 }
  end
  raise "Vulkan mismatches: #{mismatches.join("; ")}" unless mismatches.empty?
  first = actual.dup
  rgba.upload(0, 0, 1, 1, [0, 255, 255, 255].pack("C*"))
  raise "Vulkan texture revision was ignored" if vulkan.render(scene, clear: "#111") == first
  raise "Vulkan retained frame temporaries" unless vulkan.instance_variable_get(:@arena).empty?
  begin
    vulkan.resize(-1, 32)
  rescue ArgumentError
    raise "invalid resize released the Vulkan device" unless vulkan.render(scene, clear: "#111").bytesize == 64 * 64 * 4
  else
    raise "invalid Vulkan resize was accepted"
  end
  vulkan.resize(32, 32)
  raise "Vulkan resize did not rebuild frame resources" unless vulkan.render(scene, clear: "#111").bytesize == 32 * 32 * 4
  raise "Vulkan retained resize temporaries" unless vulkan.instance_variable_get(:@arena).empty?
  raise "Vulkan produced no draw calls" unless vulkan.draw_calls&.positive?
  puts "Vulkan Scene: #{vulkan.device_name}, #{vulkan.draw_calls} draw calls"
ensure
  vulkan.release
  software.release
end
