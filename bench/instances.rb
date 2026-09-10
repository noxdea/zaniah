# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
require "zaniah/gpu/instance_packing"
require "json"

scene = Zaniah::Scene.new
10_000.times { |index| scene.quad(index % 100, index / 100, 1, 1, color: "#fff") }
10.times { Zaniah::GPU::InstancePacking.pack(scene) }
timings, allocations = [], []
30.times do
  before = GC.stat(:total_allocated_objects)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  Zaniah::GPU::InstancePacking.pack(scene)
  timings << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
  allocations << GC.stat(:total_allocated_objects) - before
end
result = {operation: "CPU pack 10,000 instances (not complete UI frame)", median_ms: timings.sort[15], median_objects: allocations.sort[15]}
puts JSON.generate(result)
abort "instance encoding exceeds 6ms" if ENV["BUDGET"] == "1" && result[:median_ms] > 6
abort "instance encoding exceeds 200 objects" if ENV["BUDGET"] == "1" && result[:median_objects] >= 200
