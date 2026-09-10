# frozen_string_literal: true

require_relative "test_helper"

class InputClipTest < Minitest::Test
  def test_overflow_clips_child_hits_and_restores_sibling_clip
    window = Zaniah::Platform.open_window(width: 200, height: 200)
    clicks = []
    root = Zaniah::Div.new.flex_col
    parent = Zaniah::Div.new.h(50).overflow_hidden
    parent.child(Zaniah::Div.new.style(position: :absolute, top: 60, width: 100, height: 30).on_click { clicks << :hidden })
    root.child(parent).child(Zaniah::Div.new.h(50).on_click { clicks << :visible })
    window.render(root)
    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(10, 65), :left, [], 1))
    assert_equal [:visible], clicks
    window.close
  end
  def test_drag_capture_continues_outside_element_until_mouse_up
    window = Zaniah::Platform.open_window(width: 200, height: 200)
    positions = []
    element = Zaniah::Div.new.child(Zaniah::Div.new.w(30).h(30).on_drag { |event, _| positions << event.position.x })
    window.render(element)
    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(10, 10), :left, [], 1))
    window.input(Zaniah::Input::MouseMove.new(Zaniah::Point.new(150, 150), []))
    window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(150, 150), :left, []))
    window.input(Zaniah::Input::MouseMove.new(Zaniah::Point.new(180, 150), []))
    assert_equal [150], positions
    window.close
  end
  def test_key_up_does_not_dispatch_an_action
    map = Zaniah::Input::Keymap.new.bind("ctrl-s", :save)
    dispatcher = Zaniah::Input::Dispatcher.new(keymap: map)
    focus = Zaniah::Input::FocusHandle.new
    count = 0
    focus.on_action = ->(_) { count += 1 }
    dispatcher.focus(focus)
    window = Zaniah::Platform.open_window(width: 10, height: 10)
    window.instance_variable_set(:@dispatcher, dispatcher)
    window.input(Zaniah::Input::KeyDown.new("ctrl-s", false))
    window.input(Zaniah::Input::KeyUp.new("ctrl-s"))
    assert_equal 1, count
    window.close
  end
end
