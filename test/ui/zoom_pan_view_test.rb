# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"
require "zaniah/ui/zoom_pan_view"

class ZoomPanViewTest < Minitest::Test
  def test_fit_zoom_to_and_pointer_anchor
    view = Zaniah::UI::ZoomPanView.new(Zaniah::Div.new.w(400).h(200), min_zoom: 0.25, max_zoom: 4).w(200).h(100)
    window = Zaniah::Platform.open_window(width: 200, height: 100)
    window.render(view)

    assert view.fit
    assert_equal 0.5, view.zoom
    assert_equal [:group, 0.5], [view.accessibility_node(nil).role, view.accessibility_node(nil).value]
    window.render(view)
    assert_equal Zaniah::Point.new(200, 100), view.view_to_content(Zaniah::Point.new(100, 50))

    assert view.zoom_to(Zaniah::Bounds.new(100, 50, 100, 50))
    assert_equal 2.0, view.zoom
    window.render(view)
    assert_equal Zaniah::Point.new(150, 75), view.view_to_content(Zaniah::Point.new(100, 50))

    window.input(Zaniah::Input::Magnify.new(Zaniah::Point.new(100, 50), 0.25, :changed))
    assert_equal 2.5, view.zoom
    assert_equal Zaniah::Point.new(150, 75), view.view_to_content(Zaniah::Point.new(100, 50))
  ensure
    window&.close
  end

  def test_keyboard_and_control_wheel
    view = Zaniah::UI::ZoomPanView.new(Zaniah::Div.new.w(300).h(200)).w(200).h(100)
    window = Zaniah::Platform.open_window(width: 200, height: 100)
    window.render(view)
    window.dispatcher.focus(view.focus_handle)

    window.input(Zaniah::Input::KeyDown.new("+", false))
    assert_equal 1.25, view.zoom
    window.input(Zaniah::Input::KeyDown.new("0", false))
    assert_equal 1.0, view.zoom
    window.input(Zaniah::Input::ScrollWheel.new(Zaniah::Point.new(100, 50), Zaniah::Point.new(0, -120), :changed, ["ctrl"]))
    assert_operator view.zoom, :>, 1.0
    assert_match(/\d+%/, view.tui_cells)
    refute_match(/#</, view.tui_cells)
    assert_nil window.dispatcher.keymap.dispatch("0", context: {in_zoom_pan: true, in_text_field: true})
    assert view.accessibility_action(view.accessibility_node(nil), :zoom_in)
    assert_operator view.zoom, :>, 1.0
    assert view.accessibility_action(view.accessibility_node(nil), :zoom_reset)
    assert_equal 1.0, view.zoom
  ensure
    window&.close
  end

  def test_transformed_hits_and_background_pan
    clicks = 0
    content = Zaniah::Div.new.w(50).h(50).on_click { clicks += 1 }
    view = Zaniah::UI::ZoomPanView.new(content, zoom: 2).w(200).h(100)
    window = Zaniah::Platform.open_window(width: 200, height: 100)
    window.render(view)

    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(75, 75), :left, [], 1))
    assert_equal 1, clicks
    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(150, 50), :left, [], 1))
    window.input(Zaniah::Input::MouseMove.new(Zaniah::Point.new(160, 50), []))
    window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(160, 50), :left, []))
    assert_equal Zaniah::Point.new(75, 25), view.view_to_content(Zaniah::Point.new(160, 50))
  ensure
    window&.close
  end

  def test_reset_respects_zoom_range
    view = Zaniah::UI::ZoomPanView.new(Zaniah::Div.new.w(20).h(20), zoom: 2, min_zoom: 2, max_zoom: 3)
    window = Zaniah::Platform.open_window(width: 80, height: 80)
    window.render(view)
    assert view.accessibility_action(view.accessibility_node(nil), :zoom_reset)
    assert_equal 2.0, view.zoom
  ensure
    window&.close
  end
end
