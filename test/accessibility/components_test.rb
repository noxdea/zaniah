# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../tui/components_test"

class AccessibilityComponentsTest < Minitest::Test
  ROLES = {
    Label: :text, Kbd: :text, Icon: :image, Divider: :separator, Card: :group, Badge: :text, Avatar: :image,
    Skeleton: :progressbar, EmptyState: :group, Button: :button, IconButton: :button,
    ToggleButton: :button, ButtonGroup: :group, Checkbox: :checkbox, Radio: :radio,
    RadioGroup: :radiogroup, Switch: :switch, Slider: :slider, RangeSlider: :slider,
    ProgressBar: :progressbar, Spinner: :progressbar, Meter: :meter, Tooltip: :tooltip,
    Popover: :group, ContextMenu: :menu, Menu: :menu, MenuBar: :menubar, Dropdown: :button,
    TextField: :textbox, TextArea: :textbox, SearchInput: :searchbox, PasswordInput: :textbox,
    NumberInput: :textbox, TagInput: :textbox, Select: :combobox, Combobox: :combobox,
    MultiSelect: :listbox, DatePicker: :combobox, TimePicker: :combobox, ColorPicker: :combobox,
    Tabs: :group, Scrollbar: :scrollbar, Accordion: :group, Collapsible: :button, Breadcrumb: :navigation,
    Pagination: :navigation, Toolbar: :toolbar, StatusBar: :status, Sidebar: :navigation,
    Modal: :dialog, Dialog: :dialog, Drawer: :dialog, Toast: :status, CommandPalette: :dialog,
    SplitPane: :group, PaneGrid: :group, Resizable: :group, DockPanel: :group, ListView: :list, Table: :table,
    DataGrid: :table, TreeView: :tree, Sparkline: :image, LineChart: :image, BarChart: :image,
    PieChart: :image, DonutChart: :image, ScatterChart: :image, AreaChart: :image, StackedBarChart: :image,
    FormField: :group, Form: :form, CodeEditor: :textbox, RichText: :text
  }.freeze

  def setup
    @app = Zaniah::App.new(clock: -> { 0.0 })
    @window = @app.open_window(width: 800, height: 600)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_every_public_component_exposes_a_valid_semantic_node
    examples = TUIComponentsTest.new(:unused).cases.transform_values(&:first)
    examples[:Icon] = Zaniah::UI::Icon.new(:check, label: "Complete")
    assert_equal ROLES.keys.sort, (examples.keys - [:Spacer]).sort

    examples.each do |name, component|
      @window.render(component, present: false)
      if name == :Spacer
        assert_nil @window.accessibility_tree.root, name.to_s
        next
      end
      node = @window.accessibility_tree.root
      assert_instance_of Zaniah::Accessibility::Node, node, name.to_s
      assert_equal ROLES.fetch(name), node.role, name.to_s
      assert_instance_of Zaniah::Bounds, node.bounds, name.to_s
      assert_operator node.bounds.width, :>=, 0, name.to_s
      assert_operator node.bounds.height, :>=, 0, name.to_s
      assert_semantic_tree(node, name)
    end
  end

  private

  def assert_semantic_tree(node, name)
    assert node.states.frozen?, name.to_s
    assert node.children.frozen?, name.to_s
    assert node.actions.frozen?, name.to_s
    node.children.each do |child|
      assert_instance_of Zaniah::Accessibility::Node, child, name.to_s
      assert_semantic_tree(child, name)
    end
  end
end
