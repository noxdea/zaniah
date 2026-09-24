# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"

class WindowDragRegionTest < Minitest::Test
  def test_special_hit_regions_respect_child_priority
    window = Zaniah::Platform::Headless::Window.new(width: 200, height: 100)
    close = Zaniah::Div.new.w(20).h(20).window_control(:close)
    root = Zaniah::Div.new.w(100).h(40).window_drag_region.child(close)
    window.render(root, present: false)
    assert_equal :close, window.window_region_at(Zaniah::Point.new(10, 10))
    assert_equal :drag, window.window_region_at(Zaniah::Point.new(50, 10))
    assert_nil window.window_region_at(Zaniah::Point.new(250, 10))
    assert_raises(ArgumentError) { root.window_control(:unknown) }
  ensure
    window&.close
  end

  def test_icon_button_window_control_closes_window
    window = Zaniah::Platform::Headless::Window.new(width: 200, height: 100)
    button = Zaniah::UI::IconButton.new(:close, label: "Close").window_control(:close)
    window.render(button, present: false)
    assert_equal :close, window.window_region_at(Zaniah::Point.new(10, 10))
    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(10, 10), :left, [], 1))
    assert window.closed?
  ensure
    window&.close
  end
end
