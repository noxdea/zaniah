# frozen_string_literal: true

require "benchmark"
require_relative "../lib/zaniah"
require_relative "../lib/zaniah/gpu/instance_packing"

font_path = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)
database = Zaniah::TextSystem::FontDB.new(paths: [font_path])
system = Zaniah::TextSystem::Renderer.new(font_db: database)
texts = Array.new(100) { |i| (format("%03d", i) + "Abcdefghij" * 10).byteslice(0, 100).freeze }
scene = Zaniah::Scene.new
spans = ENV["TEXT_SPANS"] == "1" ? Array.new(10) { |i| [i * 10, (i + 1) * 10, %w[#e06c75 #98c379 #61afef][i % 3]].freeze }.freeze : nil
paint = lambda do
  scene.clear
  texts.each_with_index do |text, i|
    line = system.layout_line(text, size: 14)
    system.paint_line(scene, line, x: 2, y: 14 + i * 16, spans: spans)
  end
end
pack = -> { Zaniah::GPU::InstancePacking.pack(scene) }
paint.call
pack.call

def median_measure
  times, allocations = [], []
  21.times do
    before = GC.stat(:total_allocated_objects)
    times << Benchmark.realtime { yield } * 1000
    allocations << GC.stat(:total_allocated_objects) - before
  end
  [times.sort[10], allocations.sort[10]]
end

paint_ms, paint_objects = median_measure(&paint)
pack_ms, pack_objects = median_measure(&pack)
total_ms, total_objects = median_measure { paint.call; pack.call }
bytes, batches = pack.call
raise "benchmark must emit exactly 10,000 visible glyphs" unless bytes.bytesize == 10_000 * Zaniah::GPU::InstancePacking::STRIDE * 4
puts "Ruby #{RUBY_VERSION} YJIT=#{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?} warm 100 lines / 10,000 glyphs syntax_spans=#{!spans.nil?}"
printf "paint=%.3fms/%dobjects pack=%.3fms/%dobjects total=%.3fms/%dobjects bytes=%d batches=%d\n", paint_ms, paint_objects, pack_ms, pack_objects, total_ms, total_objects, bytes.bytesize, batches.length
abort "cached text CPU frame exceeds 8ms" if ENV["BUDGET"] == "1" && total_ms > 8
abort "cached text CPU frame exceeds 200 objects" if ENV["BUDGET"] == "1" && total_objects >= 200
system.close
