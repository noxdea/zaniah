# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "support/budget"

window = Zaniah::Platform::Headless::Window.new(width: 1000, height: 1000)
root = Zaniah::Div.new.children(Array.new(1_000) { |index| Zaniah::Div.new.key(index).h(1) })
window.render(root)

Bench.budget("inspect 1000 elements", 5.0) { Zaniah::Inspection.snapshot(window) }
