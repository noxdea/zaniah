# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "../lib/zaniah/ui"
require_relative "support/budget"

row_count, column_count = 25, 40
panes = Array.new(row_count) do |row|
  Array.new(column_count) { |column| [[row, column].freeze, Zaniah::Div.new] }
end
grid = Zaniah::UI::PaneGrid.new(panes,
  columns: Array.new(column_count) { Zaniah.fr(1) },
  rows: Array.new(row_count) { Zaniah.fr(1) }, divider_size: 1, minimum: 0)
window = Zaniah::Platform::Headless::Window.new(width: 1_000, height: 1_000)
context = Zaniah::FrameContext.new(window)
engine = Zaniah::Layout::Engine.new
root = nil

Bench.budget("build and layout 1000-pane grid", 100.0, samples: 7) do
  root = grid.request_layout(context)
  engine.compute(root, width: 1_000, height: 1_000)
end
grid.prepaint(root.bounds, nil, context)
Bench.budget("resize pane-grid divider", 10.0, samples: 7) do
  1_000.times { |index| grid.resize(:columns, index % (column_count - 1), index.even? ? 1 : -1) }
end

raise "pane-grid layout lost panes" unless grid.pane_ids.length == 1_000
window.close
