# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"
require "open3"
require "rbconfig"

class UIComponentsTest < Minitest::Test
  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 360, height: 240)
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

  def test_component_protocol_and_extensible_variants
    Zaniah::UI::Button.variants[:variant][:brand] = ->(theme) do
      {background: theme.colors.success, hover: theme.colors.success, foreground: theme.colors.text_inverse, border: theme.colors.success}
    end
    button = render(Zaniah::UI::Button.new("Ship", variant: :brand).test_id("ship"))

    assert_instance_of Zaniah::Layout::Node, button.layout_node
    assert_equal "ship", button.root.test_id
    assert_operator @window.scene.commands.length, :>, 0
  ensure
    Zaniah::UI::Button.variants[:variant].delete(:brand)
  end

  def test_component_library_is_opt_in
    lib = File.expand_path("../../lib", __dir__)
    _output, error, status = Open3.capture3(RbConfig.ruby, "-I#{lib}", "-e",
      'require "zaniah"; abort "Button loaded" if defined?(Zaniah::UI::Button)')

    assert status.success?, error
  end

  def test_button_pointer_and_keyboard_activation
    events = []
    button = render(Zaniah::UI::Button.new("Save").on_click { |event, _| events << event })
    @window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(10, 10), :left, [], 1))
    @window.dispatcher.focus(button.focus_handle)
    @window.input(Zaniah::Input::KeyDown.new("enter", false))

    assert_instance_of Zaniah::Input::MouseDown, events.first
    assert_nil events.last
    assert_equal :button, button.accessibility_node(nil).role

    @window.request_frame
    @window.tick
    assert_same button.focus_handle, @window.dispatcher.focused
  end

  def test_toggle_slider_and_text_field_interactions
    checkbox = render(Zaniah::UI::Checkbox.new("Ready"))
    @window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(10, 10), :left, [], 1))
    @window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(10, 10), :left, []))
    assert_equal true, checkbox.value

    slider = render(Zaniah::UI::Slider.new(value: 0, min: 0, max: 10))
    @window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(180, 10), :left, [], 1))
    @window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(180, 10), :left, []))
    assert_in_delta 5, slider.value, 0.5
    @window.dispatcher.focus(slider.focus_handle)
    @window.input(Zaniah::Input::KeyDown.new("right", false))
    assert_operator slider.value, :>, 5

    field = render(Zaniah::UI::TextField.new("", placeholder: "Name"))
    @window.dispatcher.focus(field.focus_handle)
    @window.input(Zaniah::Input::TextInput.new("Ruby"))
    assert_equal "Ruby", field.value
  end

  def test_modal_traps_focus_and_escape_closes
    button = Zaniah::UI::Button.new("OK")
    modal = render(Zaniah::UI::Modal.new(button, title: "Confirm"))
    assert_equal :dialog, modal.accessibility_node(nil).role
    @window.dispatcher.focus(button.focus_handle)
    @window.input(Zaniah::Input::KeyDown.new("esc", false))

    refute modal.open?
  end

  def test_accessibility_and_tui_contracts_cover_component_layers
    components = [
      Zaniah::UI::Label.new("Label"), Zaniah::UI::Badge.new("New"), Zaniah::UI::Avatar.new("Ruby UI"),
      Zaniah::UI::Button.new("Save"), Zaniah::UI::Checkbox.new("Check"), Zaniah::UI::Radio.new("Pick"),
      Zaniah::UI::Switch.new("Power"), Zaniah::UI::Slider.new(label: "Volume"), Zaniah::UI::ProgressBar.new(value: 40),
      Zaniah::UI::TextField.new("text", label: "Name"), Zaniah::UI::Tabs.new([["One", Zaniah::UI::Label.new("Panel")]]),
      Zaniah::UI::Modal.new(Zaniah::UI::Label.new("Body"), title: "Dialog")
    ]

    components.each do |component|
      render(component)
      assert_kind_of String, component.tui_cells
      assert component.accessibility_node(nil), component.class.name
    end
  end

  def test_placement_flips_and_clamps_to_viewport
    viewport = Zaniah::Bounds.new(0, 0, 100, 100)
    result = Zaniah::UI::Placement.place(Zaniah::Bounds.new(90, 90, 10, 10), [40, 30], viewport)

    assert_equal Zaniah::Bounds.new(60, 52, 40, 30), result
  end

  def test_window_context_menu_uses_component_overlay
    called = false
    @window.draw { Zaniah::Div.new }
    @window.context_menu([["Choose", -> { called = true }], ["Disabled", nil]], position: Zaniah::Point.new(10, 10))
    @window.tick

    assert_equal ["Choose", "Disabled"], @window.popup.labels
    @window.input(Zaniah::Input::KeyDown.new("enter", false))
    assert called
  end

  def test_every_m6_component_renders
    label = Zaniah::UI::Label.new("Content")
    items = [["One", ->(*) {}], ["Disabled", nil]]
    components = [
      label, Zaniah::UI::Icon.new(:check, label: "Check"), Zaniah::UI::Divider.new, Zaniah::UI::Spacer.new(4),
      Zaniah::UI::Card.new(label), Zaniah::UI::Badge.new("New"), Zaniah::UI::Avatar.new("Ruby UI"),
      Zaniah::UI::Skeleton.new, Zaniah::UI::EmptyState.new("Empty"), Zaniah::UI::Button.new("Button"),
      Zaniah::UI::IconButton.new(:menu, label: "Menu"), Zaniah::UI::ToggleButton.new("Toggle"),
      Zaniah::UI::ButtonGroup.new(Zaniah::UI::Button.new("One")), Zaniah::UI::Checkbox.new("Check"),
      Zaniah::UI::Radio.new("Radio"), Zaniah::UI::RadioGroup.new(%w[A B]), Zaniah::UI::Switch.new("Switch"),
      Zaniah::UI::Slider.new, Zaniah::UI::RangeSlider.new, Zaniah::UI::ProgressBar.new(value: 50),
      Zaniah::UI::Spinner.new, Zaniah::UI::Meter.new(value: 50),
      Zaniah::UI::Tooltip.new("Tip", anchor: Zaniah::Point.new(10, 10)),
      Zaniah::UI::Popover.new(label, anchor: Zaniah::Point.new(10, 10)),
      Zaniah::UI::ContextMenu.new(items), Zaniah::UI::Menu.new(items), Zaniah::UI::MenuBar.new([["File", items]]),
      Zaniah::UI::Dropdown.new("Choose", items: [["A", :a]]), Zaniah::UI::TextField.new,
      Zaniah::UI::TextArea.new, Zaniah::UI::SearchInput.new, Zaniah::UI::PasswordInput.new("secret"),
      Zaniah::UI::NumberInput.new(1), Zaniah::UI::TagInput.new(["ruby"]),
      Zaniah::UI::Tabs.new([["Tab", label]]), Zaniah::UI::Accordion.new([["Section", label]]),
      Zaniah::UI::Collapsible.new("More", label), Zaniah::UI::Breadcrumb.new(["Home"]),
      Zaniah::UI::Pagination.new(pages: 2), Zaniah::UI::Toolbar.new(label), Zaniah::UI::StatusBar.new(label),
      Zaniah::UI::Sidebar.new(label), Zaniah::UI::Modal.new(label), Zaniah::UI::Dialog.new(label),
      Zaniah::UI::Drawer.new(label), Zaniah::UI::Toast.new("Saved"), Zaniah::UI::CommandPalette.new(items, open: true)
    ]

    components.each do |component|
      render(component)
      assert_instance_of Zaniah::Layout::Node, component.layout_node, component.class.name
      assert_kind_of String, component.tui_cells, component.class.name
      assert component.accessibility_node(nil), component.class.name unless component.is_a?(Zaniah::UI::Spacer)
    end
  end
end
