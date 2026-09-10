# frozen_string_literal: true

require "benchmark"
require "tmpdir"
require_relative "../lib/zaniah"

font_path = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)
Dir.mktmpdir("zaniah-atlas-benchmark-") do |directory|
  2.times do |index|
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    system = Zaniah::TextSystem::Renderer.new(cache_dir: directory,
      font_db: Zaniah::TextSystem::FontDB.new(paths: [font_path]))
    initialize_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
    prewarm_ms = Benchmark.realtime { system.prewarm } * 1000
    count = 0
    system.instance_variable_get(:@rasters).define_singleton_method(:rasterize) { |*args, **keywords| count += 1; super(*args, **keywords) }
    scene = Zaniah::Scene.new
    draw_ms = Benchmark.realtime { system.paint_line(scene, system.layout_line("Cached ASCII glyphs: 0123456789"), x: 3.37, y: 20) } * 1000
    bytes = Dir[File.join(directory, "*.atlas")].sum { |path| File.size(path) }
    printf "%s: initialize=%.3fms prewarm=%.3fms firstpaint=%.3fms rerasterized=%d disk=%dbytes\n",
      index.zero? ? "cold/write" : "disk/reuse", initialize_ms, prewarm_ms, draw_ms, count, bytes
    raise "prewarm failed to cover all subpixel buckets" unless count.zero?
    system.end_frame
    system.close
  end
end
