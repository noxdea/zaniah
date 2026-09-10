# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"

backend = RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mingw|mswin/) ? :windows : :linux
gpu = ARGV.include?("--gl") ? :opengl : backend == :mac ? :metal : :opengl
window = Zaniah::Platform.open_window(backend: backend, gpu: gpu, width: 640, height: 400, title: "Zaniah UI native rendering")
scene = Zaniah::Scene.new
scene.quad(0, 0, 640, 400, color: "#18202b")
scene.quad(24, 24, 280, 130, color: "#46a0d8", radius: [20, 8, 20, 8], border_width: 3, border_color: "#fff")
scene.quad(180, 80, 260, 130, color: "#d35b7790", radius: 24)
texture = window.device.create_texture(2, 2, data: [255, 255, 255, 255, 80, 140, 255, 255, 80, 220, 160, 255, 0, 0, 0, 255].pack("C*"))
scene.sprite(28, 210, 120, 120, texture: texture)
scene.triangle([330, 260, 450, 340, 530, 220], color: "#f8ca72")
window.draw { scene }
window.on_input do |event|
  puts event.inspect
  window.close if event.is_a?(Zaniah::Input::KeyDown) && event.keystroke == "esc"
end
if ARGV.include?("--check")
  screens = window.displays
  raise "native display enumeration failed: #{screens.inspect}" unless screens.any? { |screen| screen.bounds.width.positive? && screen.scale_factor.positive? }
  puts "Displays: #{screens.inspect}"
  events = []
  window.on_input { |event| events << event }
  if backend == :mac
    objc = Zaniah::FFI::ObjC
    objc.send(window.view, "setMarkedText:selectedRange:replacementRange:", objc.string("にほん"), [3, 0], [(1 << 63) - 1, 0], args: [:pointer, :range, :range], result: :void)
    raise "marked text callback failed" unless events.last.is_a?(Zaniah::Input::Composition) && events.last.text == "にほん"
    objc.send(window.view, "insertText:replacementRange:", objc.string("日本"), [(1 << 63) - 1, 0], args: [:pointer, :range], result: :void)
    raise "committed text callback failed" unless events.last.is_a?(Zaniah::Input::TextInput) && events.last.text == "日本"
    window.ime_state = Zaniah::Bounds.new(20, 30, 1, 18)
    candidate = objc.send(window.view, "firstRectForCharacterRange:actualRange:", [0, 1], 0, args: [:range, :pointer], result: :rect)
    raise "IME candidate rectangle failed" unless candidate.last(2) == [1, 18]
  elsif backend == :linux && window.is_a?(Zaniah::Platform::Linux::Window) && ENV["ZANIAH_CHECK_INPUT"]
    system("xdotool", "windowfocus", window.handle.to_s, "key", "a", "mousemove", "--window", window.handle.to_s, "40", "40", "click", "1", "click", "5") or raise "xdotool input failed"
    3.times { window.tick }
    raise "X11 keyboard text missing: #{events.inspect}" unless events.any? { |event| event.is_a?(Zaniah::Input::TextInput) && event.text == "a" }
    raise "X11 mouse button missing" unless events.any? { |event| event.is_a?(Zaniah::Input::MouseDown) }
    raise "X11 scroll-down direction reversed" unless events.any? { |event| event.is_a?(Zaniah::Input::ScrollWheel) && event.delta.y.positive? }
  end
  3.times { window.request_frame; window.tick }
  output = ARGV.find { |argument| argument.end_with?(".png") }
  window.write_png(output) if output
  scale = window.scale_factor
  pixels = window.device.pixels
  pixel_width = (window.content_size.width * scale).round
  actual = pixels.byteslice(((40 * scale).to_i * pixel_width + (40 * scale).to_i) * 4, 4).unpack("C4")
  expected = [70, 160, 216, 255]
  raise "GPU pixel mismatch: #{actual.inspect}" unless actual.zip(expected).all? { |a, b| (a - b).abs <= 2 }
  puts "#{window.class}/#{gpu}: pixel=#{actual.inspect}, draw_calls=#{window.device.draw_calls}, scale=#{scale}"
  if backend == :linux && window.is_a?(Zaniah::Platform::Linux::Window) && ENV["ZANIAH_CHECK_DPI"]
    # linux_smoke owns this disposable X server. Restore its resource property.
    root, property = window.instance_variable_get(:@root), window.atom("RESOURCE_MANAGER")
    previous = window.read_property(root, property, delete: false)
    begin
      changed = previous.gsub(/^Xft\.dpi:.*$/, "") + "\nXft.dpi: 192\n"
      window.property(root, property, window.atom("STRING"), changed)
      window.x(:XFlush, [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, window.display)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
      until window.scale_factor == 2
        raise "X11 DPI change was not delivered" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        window.tick
      end
      puts "X11 live DPI: #{scale} -> #{window.scale_factor}"
    ensure
      window.property(root, property, window.atom("STRING"), previous)
      window.x(:XFlush, [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, window.display)
    end
  end
  window.close
else
  window.run
end
