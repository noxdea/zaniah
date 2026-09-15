# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "../lib/zaniah/ui"
require_relative "support/budget"

items = Array.new(100_000) { |index| {id: index, label: "Node #{index}"} }
window = Zaniah::Platform::Headless::Window.new(width: 800, height: 600)
context = Zaniah::FrameContext.new(window)
engine = Zaniah::Layout::Engine.new
tree = nil

Bench.budget("build visible rows from a 100000-node tree", 40.0, samples: 7,
  setup: lambda {
    tree = Zaniah::UI::TreeView.new([{id: :root, label: "Root", children: ->(_value) { items }}], height: 320)
    tree.expand(:root)
  }) do
  root = tree.request_layout(context)
  engine.compute(root, width: 800, height: 600)
end

rendered = tree.children.length
indexed = tree.instance_variable_get(:@locations).length
raise "tree materialized rows outside the viewport" if rendered > 30 || indexed > 30

window.close
