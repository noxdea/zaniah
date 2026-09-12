# frozen_string_literal: true

require_relative "test_helper"

class TextEditingTest < Minitest::Test
  def test_pointer_keyboard_text_and_ime_editing
    text = Zaniah::Text.new("ab").editable
    window = Zaniah::Platform.open_window(width: 100, height: 30)
    window.render(text)
    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(16, 5), :left, [], 1))
    window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(16, 5), :left, []))
    assert_equal Zaniah::TextSelection.new(2), text.selection
    refute window.dispatcher.focus_visible?

    window.input(Zaniah::Input::TextInput.new("é"))
    assert_equal "abé", text.buffer.to_s
    window.input(Zaniah::Input::Composition.new("に", [3, 0]))
    window.render(text)
    assert_equal "abéに", window.text_runs.last[2]
    assert window.ime_state

    window.input(Zaniah::Input::Composition.new("", [0, 0]))
    window.input(Zaniah::Input::TextInput.new("本"))
    assert_equal "abé本", text.buffer.to_s
    window.input(Zaniah::Input::KeyDown.new("backspace", false))
    assert_equal "abé", text.buffer.to_s
    window.input(Zaniah::Input::KeyDown.new("shift-left", false))
    assert_equal "é", text.buffer.to_s.byteslice(text.selection.range)

    primary = RUBY_PLATFORM.include?("darwin") ? "cmd-a" : "ctrl-a"
    window.input(Zaniah::Input::KeyDown.new(primary, false))
    assert_equal 0...text.buffer.bytesize, text.selection.range
  ensure
    window&.close
  end

  def test_double_and_triple_click_selection
    text = Zaniah::Text.new("hello world", wrap: :word).w(50).selectable
    window = Zaniah::Platform.open_window(width: 50, height: 60)
    window.render(text)
    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(5, 5), :left, [], 2))
    assert_equal "hello", text.text.byteslice(text.selection.range)
    window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(5, 5), :left, []))
    window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(5, 5), :left, [], 3))
    assert_operator text.selection.range.size, :>, 0
  ensure
    window&.close
  end
end
