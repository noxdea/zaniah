# frozen_string_literal: true

require "zaniah"
require "zaniah/platform/linux"

window = Zaniah::Platform::Linux::Window.new(width: 100, height: 80,
  decorations: :none, min_size: Zaniah::Size.new(64, 48))
begin
  expected = Zaniah::Bounds.new(30, 40, 160, 120)
  window.frame = expected
  window.poll_events
  raise "X11 window geometry did not roundtrip" unless window.frame == expected
  raise "X11 window state lost geometry" unless window.state.frame == expected
  puts "X11 window state roundtrip passed"
ensure
  window.close
end
