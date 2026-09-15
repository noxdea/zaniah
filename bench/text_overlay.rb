# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "support/budget"

source = Array.new(1_000) { |row| "line #{row}" }.join("\n")
text = Zaniah::Text.new(source, wrap: :anywhere, line_height: 16)
100.times do |index|
  offset = source.index("line #{index * 10}") + 4
  text.inline_overlay(offset: offset, element: Zaniah::Div.new.w(24).h(14))
end
window = Zaniah::Platform::Headless::Window.new(width: 800, height: 600)
context = Zaniah::FrameContext.new(window)
text.request_layout(context)
changed = nil
changed_offset = source.index("line 501") + 4

Bench.budget("relayout one overlay row among 1000 rows", 20.0, samples: 5, setup: lambda {
  text.remove_overlay(changed) if changed
  changed = Zaniah::Div.new.w(24).h(14)
  text.inline_overlay(offset: changed_offset, element: changed)
}) do
  text.request_layout(context)
end

window.close
