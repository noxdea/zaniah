# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"

backend = RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mingw|mswin/) ? :windows : :linux
window = Zaniah::Platform.open_window(backend: backend, gpu: ARGV.include?("--gl") ? :opengl : backend == :mac ? :metal : :opengl, width: 800, height: 600)
scene = Zaniah::Scene.new
10_000.times { |i| scene.quad((i % 100) * 8, (i / 100) * 6, 7, 5, color: "#49c", radius: 1) }
window.draw { scene }
samples = 40.times.map do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  window.request_frame
  window.tick
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
end.drop(5).sort
puts "10,000 quads: median=#{samples[samples.length / 2].round(2)}ms, p95=#{samples[(samples.length * 0.95).floor].round(2)}ms, draw_calls=#{window.device.draw_calls}"
window.close
