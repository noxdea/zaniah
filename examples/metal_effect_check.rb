# frozen_string_literal: true

require_relative "../lib/zaniah"
abort "This check needs macOS and a graphical login" unless RUBY_PLATFORM.include?("darwin")

window = Zaniah::Platform.open_window(backend: :mac, gpu: :metal, width: 96, height: 72,
  title: "Metal effect check")
begin
  scene = Zaniah::Scene.new
  scene.quad(4, 4, 30, 24, color: Zaniah::Gradient.linear(angle: 0,
    stops: [[0, "#f00"], [0.5, "#0f0"], [1, "#00f"]]))
  scene.quad(38, 4, 30, 24, color: Zaniah::Gradient.conic(stops: [[0, "#f00"], [1, "#00f"]]))
  scene.shadow(28, 40, 32, 18, color: "#000", blur: 3, spread: 1, radius: 4)
  expected = Zaniah::GPU::Software.new(96, 72).render(scene, clear: "#fff")
  window.device.render(scene, clear: "#fff")
  actual = window.device.pixels
  scale = window.scale_factor
  pixel_width = (96 * scale).round
  samples = [[6, 15], [18, 15], [31, 15], [60, 16], [22, 49], [28, 49], [44, 49], [75, 49]]
  samples.each do |x, y|
    index = (y * 96 + x) * 4
    native_index = (((y + 0.5) * scale).floor * pixel_width + ((x + 0.5) * scale).floor) * 4
    left, right = expected.byteslice(index, 4).bytes, actual.byteslice(native_index, 4).bytes
    raise "effect mismatch at #{x},#{y}: #{right.inspect} != #{left.inspect}" unless
      left.zip(right).all? { |a, b| (a - b).abs <= 8 }
  end
  puts "Metal analytic shadow and gradient check: #{samples.length} samples passed"
ensure
  window.close
end
