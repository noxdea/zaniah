# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class ClipboardTest < Minitest::Test
  def test_headless_clipboard_is_per_window_memory
    first = Zaniah::Platform::Headless::Window.new
    second = Zaniah::Platform::Headless::Window.new
    assert_equal "", first.clipboard
    first.clipboard = "hello"
    assert_equal "hello", first.clipboard
    assert_equal "", second.clipboard
  ensure
    first&.close
    second&.close
  end

  def test_tui_clipboard_sends_osc_52_to_injected_output
    output = StringIO.new
    window = Zaniah::Platform::TUI::Window.new(input: StringIO.new, output: output)
    window.clipboard = "日"
    assert_equal "日", window.clipboard
    assert_equal "\e]52;c;5pel\a", output.string
  ensure
    window&.close
  end
end
