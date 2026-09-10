# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
abort "This check needs macOS and a graphical login" unless RUBY_PLATFORM.include?("darwin")

window = Zaniah::Platform.open_window(backend: :mac, gpu: :metal, width: 96, height: 72, title: "Metal state reuse check")
begin
  device, scene, checks = window.device, Zaniah::Scene.new, 0
  descriptor = device.instance_variable_get(:@render_pass)
  check = lambda do |pixels, x, y, expected|
    scale = window.scale_factor
    width = (device.width * scale).round
    actual = pixels.byteslice(((y * scale).to_i * width + (x * scale).to_i) * 4, 4).unpack("C4")
    raise "pixel (#{x}, #{y}): #{actual.inspect}, expected #{expected.inspect}" unless actual.zip(expected).all? { |a, b| (a - b).abs <= 2 }
    checks += 1
  end
  render = lambda do |clear|
    device.render(scene, clear: clear)
    raise "render-pass descriptor was not reused" unless descriptor == device.instance_variable_get(:@render_pass)
    device.pixels
  end

  clear = +"#ff000080"
  check.call(render.call(clear), 4, 4, [255, 0, 0, 128])
  clear.replace("#00ff0080")
  check.call(render.call(clear), 4, 4, [0, 255, 0, 128])
  clear = [0.0, 0.0, 1.0, 1.0]
  check.call(render.call(clear), 4, 4, [0, 0, 255, 255])
  clear[0], clear[2] = 1.0, 0.0
  check.call(render.call(clear), 4, 4, [255, 0, 0, 255])
  begin
    render.call(nil)
    raise "nil clear color was accepted"
  rescue ArgumentError
    checks += 1
  end

  scene.clip(Zaniah::Bounds.new(-5, -5, 15, 15)) { scene.quad(0, 0, 96, 72, color: "#f00") }
  scene.clip(Zaniah::Bounds.new(999, 999, 10, 10)) { scene.quad(0, 0, 96, 72, color: "#0f0") }
  scene.quad(20, 20, 12, 12, color: "#00f")
  scene.clip(Zaniah::Bounds.new(40, 4, 20, 12)) do
    scene.clip(Zaniah::Bounds.new(48, 0, 6, 16)) { scene.quad(0, 0, 96, 72, color: "#0f0") }
  end
  pixels = render.call("#000")
  check.call(pixels, 2, 2, [255, 0, 0, 255])
  check.call(pixels, 11, 11, [0, 0, 0, 255])
  check.call(pixels, 24, 24, [0, 0, 255, 255])
  check.call(pixels, 50, 8, [0, 255, 0, 255])
  check.call(pixels, 42, 8, [0, 0, 0, 255])
  check.call(pixels, 55, 8, [0, 0, 0, 255])

  texture = device.create_texture(1, 1, data: [255, 0, 0, 255].pack("C4"))
  scene.clear.sprite(36, 28, 8, 8, texture: texture)
  check.call(render.call("#000"), 40, 32, [255, 0, 0, 255])
  texture.upload(0, 0, 1, 1, [0, 255, 0, 255].pack("C4"))
  check.call(render.call("#000"), 40, 32, [0, 255, 0, 255])
  scene.clear.quad(8, 8, 32, 32, color: "#00f")
  scene.quad(8, 8, 32, 32, color: "#ff000080")
  check.call(render.call("#000"), 16, 16, [128, 0, 127, 255])

  [[120, 80], [64, 48]].each do |width, height|
    device.resize(width, height)
    scene.clear.quad(0, 0, width, height, color: "#123")
    pixels = render.call("#000")
    check.call(pixels, 2, 2, [17, 34, 51, 255])
    check.call(pixels, width - 2, height - 2, [17, 34, 51, 255])
  end
  puts "Metal state reuse: #{checks} checks passed, scale=#{window.scale_factor}"
ensure
  window.close
end
