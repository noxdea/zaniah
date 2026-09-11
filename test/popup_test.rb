# frozen_string_literal: true
require_relative "test_helper"

class PopupTest < Minitest::Test
  def test_menu_keyboard_and_mouse_do_not_edit_underlying_view
    window = Zaniah::Platform.open_window(width: 200, height: 100)
    events, selected = [], []
    window.on_input { |event| events << event }
    window.draw { Zaniah::Div.new }
    items = [["Disabled", nil], ["One", -> { selected << 1 }], ["Two", -> { selected << 2 }]]
    window.context_menu(items, position: Zaniah::Point.new(190, 90))
    window.tick
    popup = window.popup
    assert_equal ["Disabled", "One", "Two"], popup.labels
    assert_equal [false, true, true], popup.enabled
    assert_equal 1, popup.selected_index
    assert_equal Zaniah::Bounds.new(112, 14, 88, 86), popup.bounds
    assert popup.labels.frozen?
    window.input(Zaniah::Input::KeyDown.new("down", false))
    assert_equal 2, window.popup.selected_index
    window.input(Zaniah::Input::KeyDown.new("enter", false))
    assert_equal [2], selected
    assert_empty events
    window.close
  end
  def test_tooltip_delay_and_hit_exit
    now = 0.0
    window = Zaniah::Platform.open_window(width: 200, height: 100, clock: -> { now })
    window.draw { Zaniah::Div.new }
    window.offer_tooltip("Hint", position: Zaniah::Point.new(10, 10), delay: 1)
    window.tick
    refute_includes window.text_runs.map { |run| run[2] }, "Hint"
    now = 1.0
    window.tick
    assert_includes window.text_runs.map { |run| run[2] }, "Hint"
    window.input(Zaniah::Input::MouseMove.new(Zaniah::Point.new(190, 90), []))
    window.tick
    refute_includes window.text_runs.map { |run| run[2] }, "Hint"
    window.close
  end
end
