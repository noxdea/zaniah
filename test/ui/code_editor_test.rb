# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class CodeEditorTest < Minitest::Test
  class Highlighter
    attr_reader :calls, :edits
    def initialize = (@calls, @edits = [], [])
    def tokens(index, text)
      @calls << index
      text.empty? ? [] : [[0...[text.bytesize, 2].min, :keyword]]
    end
    def edited(range, value) = @edits << [range, value]
  end

  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 320, height: 120)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def render(editor)
    @window.draw { editor }
    @window.request_frame
    @window.tick
    editor
  end

  def test_virtualizes_large_buffer_and_calls_highlighter_only_for_visible_lines
    source = ("puts :ok\n" * 100_000).chomp
    highlighter = Highlighter.new
    editor = render(Zaniah::UI::CodeEditor.new(buffer: Zaniah::UI::CodeEditor::TextBufferAdapter.new(
      Zaniah::TextBuffer.new(source)), highlighter: highlighter).w(320).h(120))
    assert_operator editor.root.visible_range.size, :<, 30
    assert_operator highlighter.calls.length, :<, 30
    editor.root.scroll_y = editor.root.heights.prefix(50_000)
    render(editor)
    assert editor.root.visible_range.cover?(50_000)
    assert_operator highlighter.calls.length, :<, 60
  end

  def test_wrapped_line_has_one_logical_line_number_and_tab_edits_buffer
    editor = render(Zaniah::UI::CodeEditor.new("abcdefghij\nnext", wrap: true).w(100).h(120))
    row = editor.root.instance_variable_get(:@rows).first
    assert_operator row.paragraph.lines.length, :>, 1
    assert_equal 0, row.index
    @window.dispatcher.focus(editor.focus_handle)
    @window.input(Zaniah::Input::KeyDown.new("tab", false))
    assert_equal "  abcdefghij\nnext", editor.value
    assert_equal :insert_tab, @window.dispatcher.keymap.dispatch("tab", context: {in_code_editor: true}) if @window.dispatcher.respond_to?(:keymap)
  end

  def test_legacy_api_read_only_and_edit_notifications
    highlighter = Highlighter.new
    editor = render(Zaniah::UI::CodeEditor.new("a", highlighter: highlighter))
    @window.dispatcher.focus(editor.focus_handle)
    @window.input(Zaniah::Input::TextInput.new("b"))
    assert_equal "ba", editor.value
    assert_equal [[0...0, "b"]], highlighter.edits
    assert_equal "   1  ba", editor.tui_cells
    assert editor.text_action(:undo)
    assert_equal "a", editor.value
    assert editor.text_action(:redo)
    assert_equal "ba", editor.value
    assert editor.input(Zaniah::Input::Composition.new("候補", [6, 0]))
    assert_equal "候補", editor.composition
    locked = render(Zaniah::UI::CodeEditor.new("x", read_only: true))
    assert_equal false, locked.validate_text_action(:insert_tab)
    assert_equal false, locked.input(Zaniah::Input::TextInput.new("y"))
    assert_equal "x", locked.value
  end
end
