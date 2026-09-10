# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("../../electra/lib", __dir__))
require "zaniah"
require "zaniah/gpu/vulkan"
require_relative "../../electra/examples/shaders"

device = Zaniah::GPU::Vulkan.new(width: 128, height: 128)
begin
  pixels = device.render_triangle(vertex_spirv: ExampleShaders.triangle_vertex, fragment_spirv: ExampleShaders.triangle_fragment)
  center = pixels.byteslice((64 * 128 + 64) * 4, 4).unpack("C4")
  outside = pixels.byteslice(0, 4).unpack("C4")
  raise "Vulkan triangle pixel mismatch: #{center.inspect}" unless center.zip([255, 64, 0, 255]).all? { |actual, expected| (actual - expected).abs <= 1 }
  raise "Vulkan clear pixel mismatch: #{outside.inspect}" unless outside == [0, 0, 0, 255]
  device.write_png(ARGV.first) if ARGV.first
  puts "Vulkan #{device.device_name}: triangle=#{center.inspect}, clear=#{outside.inspect}"
ensure
  device.release
end
