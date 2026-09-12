# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zaniah"
require_relative "support/budget"

window = Zaniah::Platform.open_window(width: 800, height: 600)
context = Zaniah::FrameContext.new(window)
element = Zaniah::Div.new.children(Array.new(1_000) { Zaniah::Div.new.h(1) })
root = nil

Bench.budget("layout request for 1000 elements", 3.0) { root = element.request_layout(context) }
engine = Zaniah::Layout::Engine.new
Bench.budget("layout compute for 1000 elements", 3.0) { engine.compute(root, width: 800, height: 600) }
Bench.budget("prepaint and paint for 1000 elements", 5.0) do
  window.scene.clear
  window.dispatcher.clear_hits
  element.prepaint(root.bounds, nil, context)
  element.paint(root.bounds, nil, nil, context)
end
window.close
