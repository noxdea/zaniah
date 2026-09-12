# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class AdvancedComponentsTest < Minitest::Test
  T = Zaniah

  def setup
    @app = T::App.new
    @window = @app.open_window(width: 640, height: 480)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def render(component)
    @window.draw { component }
    @window.request_frame
    @window.tick
    component
  end

  def test_advanced_components_render_with_tui_and_accessibility_contracts
    label = ->(text) { T::UI::Label.new(text) }
    components = [
      T::UI::Select.new([["Ruby", :ruby]], value: :ruby),
      T::UI::Combobox.new([["Ruby", :ruby], ["Zig", :zig]]),
      T::UI::MultiSelect.new([["Ruby", :ruby]], value: [:ruby]),
      T::UI::DatePicker.new("2026-09-12"), T::UI::TimePicker.new("12:30"), T::UI::ColorPicker.new,
      T::UI::SplitPane.new(label.call("One"), label.call("Two")), T::UI::Resizable.new(label.call("Resize")),
      T::UI::DockPanel.new(center: label.call("Center"), top: label.call("Top")), T::UI::ListView.new(%w[One Two]),
      T::UI::CodeEditor.new("puts 1"), T::UI::RichText.new([{text: "Ruby", color: "#f00"}])
    ]

    components.each do |component|
      render(component)
      assert_kind_of String, component.tui_cells, component.class.name
      assert component.accessibility_node(nil), component.class.name
      assert_operator @window.scene.commands.length, :>, 0, component.class.name
    end
  end

  def test_combobox_and_temporal_pickers_are_keyboard_operable
    combo = render(T::UI::Combobox.new([["Ruby", :ruby], ["Zig", :zig]]))
    @window.dispatcher.focus(combo.focus_handle)
    @window.input(T::Input::KeyDown.new("down", false))
    @window.input(T::Input::KeyDown.new("enter", false))
    assert_equal :zig, combo.value

    date = render(T::UI::DatePicker.new("2026-09-12"))
    @window.dispatcher.focus(date.focus_handle)
    @window.input(T::Input::KeyDown.new("up", false))
    assert_equal "2026-09-13", date.value.iso8601

    time = render(T::UI::TimePicker.new("12:30", step: 15))
    @window.dispatcher.focus(time.focus_handle)
    @window.input(T::Input::KeyDown.new("up", false))
    assert_equal 12 * 60 + 45, time.value
  end

  def test_split_resizable_list_and_editor_keyboard_paths
    split = render(T::UI::SplitPane.new(T::UI::Label.new("One"), T::UI::Label.new("Two")))
    @window.dispatcher.focus(split.root.children[1].focus_handle)
    @window.input(T::Input::KeyDown.new("right", false))
    assert_operator split.ratio, :>, 0.5

    resizable = render(T::UI::Resizable.new(T::UI::Label.new("Body"), width: 100, height: 80))
    @window.dispatcher.focus(resizable.root.children.last.focus_handle)
    @window.input(T::Input::KeyDown.new("right", false))
    assert_operator resizable.width, :>, 100

    list = render(T::UI::ListView.new(%w[One Two Three]))
    @window.dispatcher.focus(list.focus_handle)
    @window.input(T::Input::KeyDown.new("down", false))
    assert_equal "One", list.selected_value

    editor = render(T::UI::CodeEditor.new("a"))
    @window.dispatcher.focus(editor.focus_handle)
    @window.input(T::Input::TextInput.new("b"))
    assert_equal "ba", editor.value
  end
end
