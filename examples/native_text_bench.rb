# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
require "zaniah/gpu/instance_packing"

backend = RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mingw|mswin/) ? :windows : :linux
gpu = ARGV.include?("--gl") ? :opengl : backend == :mac ? :metal : :opengl
font_path = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)
database = Zaniah::TextSystem::FontDB.new(paths: [font_path])
system = Zaniah::TextSystem::Renderer.new(font_db: database)
window = Zaniah::Platform.open_window(backend: backend, gpu: gpu, width: 800, height: 640, title: "Cached 10,000-glyph text check")
system.scale_factor = window.scale_factor
texts = Array.new(100) { |i| (format("%03d", i) + "Abcdefghij" * 10).byteslice(0, 100).freeze }
scene = Zaniah::Scene.new
window.draw do
  scene.clear
  texts.each_with_index do |text, i|
    system.paint_line(scene, system.layout_line(text, size: 7), x: 4, y: 8 + i * 6, color: "#fff")
  end
  scene
end

samples, allocations = [], []
40.times do |i|
  before = GC.stat(:total_allocated_objects)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  window.request_frame
  window.tick
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
  objects = GC.stat(:total_allocated_objects) - before
  if i >= 5
    samples << elapsed
    allocations << objects
  end
end
bytes, batches = Zaniah::GPU::InstancePacking.pack(scene)
raise "expected 10,000 packed glyphs" unless bytes.bytesize == 10_000 * 96
pixels = window.device.pixels
ink, offset = 0, 0
while offset < pixels.bytesize
  ink += 1 if pixels.getbyte(offset) > 20
  offset += 4
end
raise "native packed text readback was empty" unless ink > 1000
output = ARGV.find { |argument| argument.end_with?(".png") }
window.write_png(output) if output
calls = 0
trace = TracePoint.new(:c_call) { |event| calls += 1 if event.method_id == :call && event.defined_class == Fiddle::Function }
trace.enable { window.request_frame; window.tick }
puts "#{gpu}: 10,000 glyphs, present median=#{samples.sort[samples.length / 2].round(3)}ms p95=#{samples.sort[(samples.length * 0.95).floor].round(3)}ms allocations=#{allocations.sort[allocations.length / 2]} Fiddle calls=#{calls}"
puts "readback=#{ink} ink pixels, #{bytes.bytesize} instance bytes, batches=#{batches.length}, draw_calls=#{window.device.draw_calls}, scale=#{window.scale_factor}"
require "digest"
puts "rgba_sha256=#{Digest::SHA256.hexdigest(pixels)}"
if ARGV.include?("--allocations")
  require "objspace"
  GC.start
  generation = GC.count
  previously_disabled = GC.disable
  begin
    ObjectSpace.trace_object_allocations_start
    window.request_frame
    window.tick
    ObjectSpace.trace_object_allocations_stop
    sites = Hash.new(0)
    ObjectSpace.each_object do |object|
      file = ObjectSpace.allocation_sourcefile(object)
      next unless file && ObjectSpace.allocation_generation(object) == generation
      sites[[file, ObjectSpace.allocation_sourceline(object), object.class]] += 1
    end
    sites.sort_by { |_, count| -count }.first(25).each { |(file, line, type), count| puts "#{count} #{type} #{file}:#{line}" }
  ensure
    ObjectSpace.trace_object_allocations_stop
    ObjectSpace.trace_object_allocations_clear
    GC.enable unless previously_disabled
  end
end
system.close
window.close
if ARGV.include?("--budget")
  raise "native cached text frame exceeds 8ms median" if samples.sort[samples.length / 2] > 8
  raise "native cached text frame exceeds 200 objects" if allocations.sort[allocations.length / 2] >= 200
end
