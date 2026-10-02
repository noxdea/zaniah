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
      T::UI::PaneGrid.new([[[:one, label.call("One")], [:two, label.call("Two")]]],
        columns: [T.fr(1), T.fr(1)], rows: [T.fr(1)]),
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

  def test_dropdowns_display_option_captions_and_keep_values_when_selected
    items = [["Dark theme", :dark], ["Light theme", :light]]
    controls = [T::UI::Dropdown.new("Theme", items: items, value: :dark),
      T::UI::Select.new(items, label: "Theme", value: :dark)]
    controls.each do |control|
      changes = []
      control.on_change { |value, *_| changes << value }
      @window.render(control, present: false)
      assert_equal "Dark theme", control.root.label
      assert_includes control.tui_cells, "Dark theme"
      assert_equal "Dark theme", control.accessibility_node(nil).value
      assert_equal :dark, control.value
      @window.dispatcher.focus(control.focus_handle, origin: :keyboard)
      assert @window.input(T::Input::KeyDown.new("enter", false))
      @window.render(control, present: false)
      @window.input(T::Input::KeyDown.new("down", false))
      @window.input(T::Input::KeyDown.new("enter", false))
      @window.render(control, present: false)
      assert_equal :light, control.value
      assert_equal [:light], changes
      assert_equal "Light theme", control.root.label
      assert_includes control.tui_cells, "Light theme"
      assert_equal "Light theme", control.accessibility_node(nil).value
    end
    disabled = T::UI::Select.new(items, label: "Theme", value: :light, disabled: true)
    @window.render(disabled, present: false)
    assert_equal "Light theme", disabled.root.label
    assert_equal :light, disabled.value
    assert disabled.accessibility_node(nil).states[:disabled]
    refute T::Accessibility.perform(@window, disabled.root.accessibility_node(nil), :press)
    fallback = T::UI::Select.new(["Ruby"], value: "Other")
    @window.render(fallback, present: false)
    assert_equal "Other", fallback.root.label
    boolean = T::UI::Select.new([["Disabled", false]], value: false)
    @window.render(boolean, present: false)
    assert_equal "Disabled", boolean.root.label
    assert_equal false, boolean.value
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
