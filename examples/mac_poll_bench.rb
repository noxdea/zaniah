# frozen_string_literal: true

# Measures native event retrieval only, not whole-application idle CPU.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
require "json"
abort "Cocoa requires macOS" unless RUBY_PLATFORM.include?("darwin")

window = Zaniah::Platform.open_window(backend: :mac, width: 320, height: 200, title: "Cocoa event retrieval benchmark")
app = Zaniah::Platform::Mac::App.instance
100.times { app.poll }
samples = Array.new(15) do
  GC.start
  allocations = GC.stat(:total_allocated_objects)
  cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
  200.times { app.poll }
  elapsed = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu
  [(GC.stat(:total_allocated_objects) - allocations) / 200.0, elapsed * 1_000_000 / 200]
end
puts JSON.generate(ruby: RUBY_DESCRIPTION, yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
  samples: samples.length, polls_per_sample: 200,
  median_objects_per_poll: samples.map(&:first).sort[samples.length / 2],
  median_cpu_microseconds_per_poll: samples.map(&:last).sort[samples.length / 2])
window.close
