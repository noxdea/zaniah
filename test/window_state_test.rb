# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/zaniah/window_state"

class WindowStateTest < Minitest::Test
  def test_roundtrip_and_wayland_origin
    [Zaniah::Bounds.new(10, 20, 640, 480), Zaniah::Bounds.new(nil, nil, 640, 480)].each do |frame|
      state = Zaniah::WindowState.new(frame: frame, display_id: "display-1", maximized: true, fullscreen: false)
      assert_equal state, Zaniah::WindowState.from_h(state.to_h)
      assert_equal state, Zaniah::WindowState.from_h(JSON.parse(JSON.generate(state.to_h)))
    end
  end

  def test_rejects_invalid_saved_geometry_and_flags
    valid = {frame: {x: 0, y: 0, width: 640, height: 480}, display_id: 0, maximized: false, fullscreen: false}
    [{x: nil, y: 0, width: 640, height: 480}, {x: 0, y: 0, width: -1, height: 480}].each do |frame|
      assert_raises(ArgumentError) { Zaniah::WindowState.from_h(valid.merge(frame: frame)) }
    end
    assert_raises(ArgumentError) { Zaniah::WindowState.from_h(valid.merge(maximized: "false")) }
  end

  def test_headless_state_transitions_and_callbacks
    window = Zaniah::Platform::Headless::Window.new(width: 640, height: 480)
    changes = []
    window.on_state_change { |state| changes << state }
    assert_raises(ArgumentError) { window.frame = Zaniah::Bounds.new(nil, nil, 500, 400) }
    window.frame = Zaniah::Bounds.new(20, 30, 500, 400)
    assert_equal [20, 30, 500, 400], [window.frame.x, window.frame.y, window.content_size.width, window.content_size.height]
    window.maximize
    assert window.maximized?
    window.minimize
    assert window.minimized?
    window.restore
    refute window.maximized?
    refute window.minimized?
    assert_equal Zaniah::Bounds.new(20, 30, 500, 400), window.frame
    window.toggle_fullscreen
    assert window.fullscreen?
    window.restore
    refute window.fullscreen?
    assert_equal window.state, changes.last
  ensure
    window&.close
  end

  def test_window_decoration_options_are_validated_and_preserved
    window = Zaniah::Platform.open_window(decorations: :none, transparent: true,
      min_size: Zaniah::Size.new(320, 200), resizable: false,
      traffic_lights: Zaniah::Point.new(12, 14))
    assert_equal :none, window.decorations
    assert window.transparent
    refute window.resizable
    assert_equal Zaniah::Size.new(320, 200), window.min_size
    assert_equal Zaniah::Point.new(12, 14), window.traffic_lights
    assert_raises(ArgumentError) { Zaniah::Platform.open_window(decorations: :custom) }
  ensure
    window&.close
  end

  def test_restore_state_uses_primary_display_and_keeps_titlebar_visible
    window = Zaniah::Platform::Headless::Window.new(width: 640, height: 480)
    primary = Zaniah::Platform::Display.new(2, "Primary", Zaniah::Bounds.new(100, 100, 800, 600), 1, true)
    window.define_singleton_method(:displays) { [primary] }
    saved = Zaniah::WindowState.new(frame: Zaniah::Bounds.new(5000, 5000, 640, 480),
      display_id: 999, maximized: false, fullscreen: false)
    result = window.restore_state(saved.to_h)
    assert_equal 2, result.display_id
    assert_equal 852, result.frame.x
    assert_equal 668, result.frame.y
    wayland = saved.to_h.merge(frame: {x: nil, y: nil, width: 400, height: 300})
    assert_equal Zaniah::Bounds.new(100, 100, 400, 300), window.restore_state(wayland).frame
  ensure
    window&.close
  end
end
