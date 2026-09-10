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
    window.input(Zaniah::Input::KeyDown.new("down", false))
    window.input(Zaniah::Input::KeyDown.new("enter", false))
    assert_equal [2], selected
    assert_empty events
    window.close
  end
  def test_tooltip_delay_and_hit_exit
    window = Zaniah::Platform.open_window(width: 200, height: 100)
    window.draw { Zaniah::Div.new }
    window.offer_tooltip("Hint", position: Zaniah::Point.new(10, 10), delay: 0)
    window.tick
    assert_includes window.text_runs.map { |run| run[2] }, "Hint"
    window.input(Zaniah::Input::MouseMove.new(Zaniah::Point.new(190, 90), []))
    window.tick
    refute_includes window.text_runs.map { |run| run[2] }, "Hint"
    window.close
  end
end
