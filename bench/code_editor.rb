# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zaniah"
require "zaniah/ui"
require_relative "support/budget"

source = ("value = compute(123)\n" * 100_000).chomp
window = Zaniah::Platform::Headless::Window.new(width: 800, height: 600)
window.text_system = Zaniah::Platform::TUI::TextRenderer.new
context = Zaniah::FrameContext.new(window)
engine = Zaniah::Layout::Engine.new
editor = Zaniah::UI::CodeEditor.new(source).w(800).h(600)

frame = lambda do
  window.scene.clear
  window.text_system.start_frame
  node = editor.request_layout(context)
  engine.compute(node, width: 800, height: 600)
  editor.prepaint(node.bounds, nil, context)
  editor.paint(node.bounds, nil, nil, context)
  raise "code editor laid out non-viewport lines" if editor.root.visible_range.size > 100
end
frame.call
position = 0
Bench.budget("code editor 100k lines scroll", 16.67, warmup: 3, samples: 23,
  setup: lambda {
    position += 4_199
    editor.root.scroll_y = (position % 99_000) * 18.2
  }, &frame)
window.close
