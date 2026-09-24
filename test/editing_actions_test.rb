# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"
require "stringio"

class EditingActionsTest < Minitest::Test
  T = Zaniah

  def setup
    @app = T::App.new
    @window = @app.open_window(width: 480, height: 240,
      keymap: T::Input::Keymap.default_ui(platform: "darwin"))
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def render(component)
    @window.render(component, present: false)
    @window.dispatcher.focus(component.focus_handle)
    component
  end

  def test_desktop_keymaps_and_tui_do_not_assign_conflicting_shortcuts
    assert_equal %i[undo redo cut copy paste select_all], T::Input::StandardActions::EDIT
    mappings = {
      "darwin" => ["cmd-z", "cmd-shift-z", "cmd-x", "cmd-c", "cmd-v", "cmd-a", "alt-left", "cmd-up"],
      "mingw" => ["ctrl-z", "ctrl-y", "ctrl-x", "ctrl-c", "ctrl-v", "ctrl-a", "ctrl-left", "ctrl-home"],
      "linux" => ["ctrl-z", "ctrl-shift-z", "ctrl-x", "ctrl-c", "ctrl-v", "ctrl-a", "ctrl-left", "ctrl-home"]
    }
    expected = %i[undo redo cut copy paste select_all word_left document_start]
    mappings.each do |platform, keys|
      keymap = T::Input::Keymap.default_ui(platform: platform)
      assert_equal expected, keys.map { |key| keymap.dispatch(key, context: {in_text_field: true}) }, platform
      assert_equal :line_up, keymap.dispatch("up", context: {in_text_field: true, multiline: true})
      assert_equal :line_down, keymap.dispatch("down", context: {in_text_field: true, multiline: true})
    end
    assert_nil T::Input::Keymap.default_ui(platform: "linux").dispatch("ctrl-y")
    tui = T::Input::Keymap.default_ui(platform: :tui)
    %w[ctrl-a ctrl-c ctrl-x ctrl-v ctrl-z ctrl-shift-z].each { |key| assert_nil tui.dispatch(key) }
  end

  def test_text_field_copy_cut_paste_and_history_share_dispatch_path
    field = render(T::UI::TextField.new("hello world"))
    editor = field.focus_handle.owner
    editor.selection = T::TextSelection.new(0, 5)
    @window.input(T::Input::KeyDown.new("cmd-c", false))
    assert_equal "hello", @window.clipboard
    assert_equal :enabled, @window.dispatcher.available?(:cut)

    @window.tick
    refute @window.dirty?
    assert @window.dispatcher.perform(:cut, source: :menu)
    assert @window.dirty?
    assert_equal " world", field.value
    assert_equal :disabled, @window.dispatcher.available?(:copy)
    assert @window.dispatcher.perform(:undo, source: :menu)
    assert_equal "hello world", field.value
    assert @window.dispatcher.perform(:redo, source: :menu)
    assert_equal " world", field.value
    editor.selection = T::TextSelection.new(0)
    assert @window.dispatcher.perform(:paste, source: :menu)
    assert_equal "hello world", field.value

    field.buffer.set_composition("日")
    assert_equal :disabled, @window.dispatcher.available?(:paste)
    assert_equal :disabled, @window.dispatcher.available?(:undo)
    refute @window.dispatcher.perform(:paste, source: :menu)
  end

  def test_text_field_undo_and_redo_follow_buffer_history
    field = render(T::UI::TextField.new("before"))
    assert_equal :disabled, @window.dispatcher.available?(:undo)
    assert_equal :disabled, @window.dispatcher.available?(:redo)
    refute @window.dispatcher.perform(:undo, source: :menu)

    field.buffer.insert(field.buffer.bytesize, " after")
    assert_equal :enabled, @window.dispatcher.available?(:undo)
    assert_equal :disabled, @window.dispatcher.available?(:redo)
    assert @window.dispatcher.perform(:undo, source: :menu)
    assert_equal :disabled, @window.dispatcher.available?(:undo)
    assert_equal :enabled, @window.dispatcher.available?(:redo)
    assert @window.dispatcher.perform(:redo, source: :menu)
    assert_equal :enabled, @window.dispatcher.available?(:undo)
    assert_equal :disabled, @window.dispatcher.available?(:redo)
  end

  def test_paste_validation_does_not_read_clipboard
    field = render(T::UI::TextField.new)
    reads = 0
    @window.define_singleton_method(:clipboard) { reads += 1; "paste" }
    assert_equal :enabled, @window.dispatcher.available?(:paste)
    assert_equal 0, reads
    assert @window.dispatcher.perform(:paste, source: :menu)
    assert_equal "paste", field.value
    assert_equal 1, reads

    rich = render(T::UI::RichText.new("", editable: true))
    assert_equal :enabled, @window.dispatcher.available?(:paste)
    assert_equal 1, reads
    assert @window.dispatcher.perform(:paste, source: :menu)
    assert_equal "paste", rich.text
    assert_equal 2, reads
  end

  def test_password_input_never_copies_or_cuts
    field = render(T::UI::PasswordInput.new("secret"))
    field.focus_handle.owner.selection = T::TextSelection.new(0, 6)
    @window.clipboard = "unchanged"
    assert_equal :disabled, @window.dispatcher.available?(:copy)
    assert_equal :disabled, @window.dispatcher.available?(:cut)
    refute @window.dispatcher.perform(:copy, source: :menu)
    refute @window.dispatcher.perform(:cut, source: :menu)
    assert_equal "unchanged", @window.clipboard
    assert_equal "secret", field.value
  end

  def test_read_only_text_can_copy_without_falling_through_to_app_cut
    @app.actions.register(:cut) { |_cx| flunk "cut escaped read-only text" }
    text = render(T::Text.new("Read only").selectable)
    text.selection = T::TextSelection.new(0, 4)
    assert @window.dispatcher.perform(:copy, source: :menu)
    assert_equal "Read", @window.clipboard
    assert_equal :disabled, @window.dispatcher.available?(:cut)
    refute @window.dispatcher.perform(:cut, source: :menu)
  end

  def test_word_line_and_document_navigation_use_grapheme_offsets
    field = render(T::UI::TextArea.new("one two\n日本 語"))
    editor = field.focus_handle.owner
    editor.selection = T::TextSelection.new(0)
    @window.input(T::Input::KeyDown.new("alt-right", false))
    assert_equal 4, editor.selection.head
    @window.input(T::Input::KeyDown.new("alt-shift-right", false))
    assert_equal 4, editor.selection.anchor
    assert_equal 8, editor.selection.head

    editor.selection = T::TextSelection.new(2)
    @window.input(T::Input::KeyDown.new("down", false))
    assert_equal 14, editor.selection.head
    @window.dispatcher.perform(:document_end, source: :menu)
    assert_equal field.value.bytesize, editor.selection.head
    @window.dispatcher.perform(:document_start, source: :menu)
    assert_equal 0, editor.selection.head
  end

  def test_rich_text_restores_styled_spans_and_blocks_ime_undo
    rich = render(T::UI::RichText.new([{text: "Hello", bold: true}, " world"], editable: true))
    rich.selection = T::TextSelection.new(0, 5)
    assert @window.dispatcher.perform(:cut, source: :menu)
    assert_equal "Hello", @window.clipboard
    assert_equal " world", rich.text
    assert_equal [], rich.spans

    assert @window.dispatcher.perform(:undo, source: :menu)
    assert_equal "Hello world", rich.text
    assert_equal [{text: "Hello", bold: true}, {text: " world"}], rich.runs
    assert @window.dispatcher.perform(:redo, source: :menu)
    assert_equal " world", rich.text

    rich.buffer.set_composition("日")
    assert_equal :disabled, @window.dispatcher.available?(:undo)
    assert_equal :disabled, @window.dispatcher.available?(:paste)
  end

  def test_read_only_rich_text_can_copy_but_cannot_cut
    rich = render(T::UI::RichText.new("Read only"))
    rich.selection = T::TextSelection.new(0, 4)
    assert_equal :enabled, @window.dispatcher.available?(:copy)
    assert @window.dispatcher.perform(:copy, source: :menu)
    assert_equal "Read", @window.clipboard
    assert_equal :disabled, @window.dispatcher.available?(:cut)
    refute @window.dispatcher.perform(:cut, source: :menu)
    assert_equal "Read only", rich.text
  end

  def test_read_only_rich_text_preserves_in_text_binding_context
    keymap = T::Input::Keymap.new.bind("ctrl-r", :custom, context: "in_text")
    window = @app.open_window(keymap: keymap)
    rich = T::UI::RichText.new("Read only")
    window.render(rich, present: false)
    window.dispatcher.focus(rich.focus_handle)

    assert_equal :custom, window.dispatcher.key("ctrl-r")
  ensure
    window&.close
  end

  def test_rich_text_undo_restores_style_only_edits
    rich = render(T::UI::RichText.new("Title", editable: true))
    rich.apply(0...5, bold: true)
    rich.paragraph_style(0...5, align: :center)
    assert @window.dispatcher.perform(:undo, source: :menu)
    assert_equal({}, rich.paragraph_styles.first)
    assert_equal true, rich.spans.first.style[:bold]
    assert @window.dispatcher.perform(:undo, source: :menu)
    assert_empty rich.spans
    assert @window.dispatcher.perform(:redo, source: :menu)
    assert_equal true, rich.spans.first.style[:bold]
  end

  def test_tui_window_uses_tui_keymap_even_on_desktop_host
    window = T::Platform::TUI::Window.new(input: StringIO.new, output: StringIO.new)
    assert_nil window.dispatcher.key("ctrl-z")
    assert_nil window.dispatcher.key("ctrl-c")
  ensure
    window&.close
  end
end
