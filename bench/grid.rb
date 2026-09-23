# frozen_string_literal: true

require "benchmark"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zaniah"
require "zaniah/ui"

rows, columns, rendered = 1_000_000, 16_000, 0
window = Zaniah::Platform::Headless::Window.new(width: 800, height: 600)
context = Zaniah::FrameContext.new(window)
engine = Zaniah::Layout::Engine.new
grid = nil
construction = Benchmark.realtime do
  grid = Zaniah::UI::Grid.new(rows: rows, columns: columns, frozen_rows: 1, frozen_columns: 1,
    row_height: ->(row) { row.zero? ? 32 : 24 }, column_width: ->(column) { column.zero? ? 180 : 96 }) do |row, column, _bounds, _cx|
    rendered += 1
    "#{row}:#{column}"
  end.w(800).h(600)
end

def render_grid_frame(grid, window, context, engine, row, column, stages = nil)
  grid.scroll_to(row: row, column: column)
  window.scene.clear
  window.dispatcher.clear_hits
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  root = grid.request_layout(context)
  stages[:build] << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000 if stages
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  engine.compute(root, width: 800, height: 600)
  stages[:layout] << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000 if stages
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  grid.prepaint(root.bounds, nil, context)
  grid.paint(root.bounds, nil, nil, context)
  stages[:paint] << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000 if stages
end

render_grid_frame(grid, window, context, engine, 0, 0)
grid.scroll_to(row: 500_000, column: 8_000)
rendered_before = rendered
stages = {build: [], layout: [], paint: []}
times = 23.times.map do |index|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  render_grid_frame(grid, window, context, engine, 500_000 + index * 24, 8_000 + index * 4, stages)
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
end
median = times.sort[times.length / 2]
frames = times.length
visible_cells = (rendered - rendered_before) / frames
puts "million-row, 16k-column index construction: #{(construction * 1000).round(3)} ms"
puts "two-axis viewport frame median (build/layout/prepaint/paint): #{median.round(3)} ms"
stages.each { |name, values| puts "  #{name} median: #{values.sort[values.length / 2].round(3)} ms" }
puts "average cells constructed per frame: #{visible_cells.round(1)}"
raise "grid constructed non-viewport cells" if rendered - rendered_before > frames * 1_000
abort "virtual grid frame exceeds 16.67ms" if ENV["BUDGET"] == "1" && median > 16.67
window.close
