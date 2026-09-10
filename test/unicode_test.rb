# frozen_string_literal: true
require_relative "test_helper"
require "stringio"

class UnicodeTest < Minitest::Test
  def test_grapheme_cell_width_uses_pinned_unicode_tables
    {"日本" => 4, "e\u0301" => 1, "👩🏽‍💻" => 2, "🇯🇵" => 2, "1️⃣" => 2}.each do |text, width|
      assert_equal width, Zaniah::Unicode.width(text)
    end
  end
  def test_tui_wide_cells_and_control_bytes_cannot_inject_terminal_commands
    output = StringIO.new
    window = Zaniah::Platform.open_window(backend: :tui, width: 160, height: 40, output: output)
    window.draw { Zaniah::Text.new("日🙂e\u0301\e[31m") }
    window.tick
    assert_includes output.string, "日🙂e\u0301␛[31m"
    refute_includes output.string, "\e[31m"
    assert_equal 20, Zaniah::Unicode.width(output.string.gsub(/\e\[[\d;]*[mH]/, "").split("\r\n").first)
    window.close
  end
end
