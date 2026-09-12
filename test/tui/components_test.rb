# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class TUIComponentsTest < Minitest::Test
  CALLBACK = ->(*) {}
  ITEMS = [["One", CALLBACK], ["Two", nil]].freeze
  ROWS = [{id: 1, name: "Alpha"}, {id: 2, name: "Beta"}].freeze
  COLUMNS = [{key: :id, label: "ID"}, {key: :name, label: "Name"}].freeze

  def cases
    label = ->(text) { Zaniah::UI::Label.new(text) }
    {
      Label: [label["Hello"], "Hello"], Icon: [Zaniah::UI::Icon.new(:check), "✓"],
      Divider: [Zaniah::UI::Divider.new, "─"], Spacer: [Zaniah::UI::Spacer.new, ""],
      Card: [Zaniah::UI::Card.new(label["Body"]), "┌ card ┐"], Badge: [Zaniah::UI::Badge.new("New"), "[New]"],
      Avatar: [Zaniah::UI::Avatar.new("Ruby UI"), "(RU)"], Skeleton: [Zaniah::UI::Skeleton.new, "░░░"],
      EmptyState: [Zaniah::UI::EmptyState.new("Empty", message: "Try again"), "Empty — Try again"],
      Button: [Zaniah::UI::Button.new("Save"), "[ Save ]"], IconButton: [Zaniah::UI::IconButton.new(:menu, label: "Menu"), "[☰]"],
      ToggleButton: [Zaniah::UI::ToggleButton.new("Pin", value: true), "[ Pin ]"],
      ButtonGroup: [Zaniah::UI::ButtonGroup.new(Zaniah::UI::Button.new("A"), Zaniah::UI::Button.new("B")), "[ A ] [ B ]"],
      Checkbox: [Zaniah::UI::Checkbox.new("Check", value: :mixed), "[-] Check"], Radio: [Zaniah::UI::Radio.new("Radio", value: true), "(o) Radio"],
      RadioGroup: [Zaniah::UI::RadioGroup.new([["A", :a], ["B", :b]], value: :b), "( ) A (o) B"],
      Switch: [Zaniah::UI::Switch.new("Power", value: true), "[on ] Power"],
      Slider: [Zaniah::UI::Slider.new(value: 50, label: "Level"), "Level [=====-----] 50.0"],
      RangeSlider: [Zaniah::UI::RangeSlider.new(value: [20, 80], label: "Range"), "Range [20.0..80.0]"],
      ProgressBar: [Zaniah::UI::ProgressBar.new(value: 40), "[====------]"], Spinner: [Zaniah::UI::Spinner.new, "◌ Loading"],
      Meter: [Zaniah::UI::Meter.new(value: 70), "[=======---]"],
      Tooltip: [Zaniah::UI::Tooltip.new("Hint", anchor: Zaniah::Point.new(0, 0)), "Hint"],
      Popover: [Zaniah::UI::Popover.new(label["Body"], anchor: Zaniah::Point.new(0, 0)), "┌ Body ┐"],
      ContextMenu: [Zaniah::UI::ContextMenu.new(ITEMS), "> One\n  Two"], Menu: [Zaniah::UI::Menu.new(ITEMS), "> One\n  Two"],
      MenuBar: [Zaniah::UI::MenuBar.new([["File", ITEMS], ["Edit", ITEMS]]), "File | Edit"],
      Dropdown: [Zaniah::UI::Dropdown.new("Choose", items: [["One", 1]], value: 1), "Choose: 1"],
      TextField: [Zaniah::UI::TextField.new("Ada", label: "Name"), "Name: [Ada]"],
      TextArea: [Zaniah::UI::TextArea.new("Line", label: "Notes"), "Notes: [Line]"],
      SearchInput: [Zaniah::UI::SearchInput.new("ruby", placeholder: "Search"), "[ruby]"],
      PasswordInput: [Zaniah::UI::PasswordInput.new("secret", label: "Password"), "Password: [******]"],
      NumberInput: [Zaniah::UI::NumberInput.new(4, label: "Count"), "Count: [4]"],
      TagInput: [Zaniah::UI::TagInput.new(%w[ruby ui], placeholder: "Tag"), "[ruby] [ui] [Tag]"],
      Select: [Zaniah::UI::Select.new([["Ruby", :ruby]], value: :ruby), "Select: [ruby ▾]"],
      Combobox: [Zaniah::UI::Combobox.new(%w[Ruby Zig], value: "Ruby", label: "Language"), "Language: [Ruby█]"],
      MultiSelect: [Zaniah::UI::MultiSelect.new(%w[GPU TUI], value: %w[GPU], label: "Targets"), "Targets: [GPU]"],
      DatePicker: [Zaniah::UI::DatePicker.new("2026-09-13"), "Date: [2026-09-13]"],
      TimePicker: [Zaniah::UI::TimePicker.new("14:30"), "Time: [14:30]"],
      ColorPicker: [Zaniah::UI::ColorPicker.new("#2563eb"), "Color: [#2563eb]"],
      Tabs: [Zaniah::UI::Tabs.new([["One", label["Panel"]], ["Two", label["Other"]]]), "[One] Two\nPanel"],
      Accordion: [Zaniah::UI::Accordion.new([["One", label["Panel"]], ["Two", label["Other"]]]), "[-] One\n[+] Two"],
      Collapsible: [Zaniah::UI::Collapsible.new("Details", label["Panel"], open: true), "[-] Details\nPanel"],
      Breadcrumb: [Zaniah::UI::Breadcrumb.new(["Home", "Page"]), "Home / Page"],
      Pagination: [Zaniah::UI::Pagination.new(page: 2, pages: 5), "Page 2/5"],
      Toolbar: [Zaniah::UI::Toolbar.new(label["Tool"]), "Tool"], StatusBar: [Zaniah::UI::StatusBar.new(label["Ready"]), "Ready"],
      Sidebar: [Zaniah::UI::Sidebar.new(label["Files"]), "Files"],
      Modal: [Zaniah::UI::Modal.new(label["Body"], title: "Modal"), "┌ Modal ┐\nBody\n└────────┘"],
      Dialog: [Zaniah::UI::Dialog.new(label["Body"], title: "Dialog"), "┌ Dialog ┐\nBody\n└────────┘"],
      Drawer: [Zaniah::UI::Drawer.new(label["Body"], title: "Drawer"), "┌ Drawer ┐\nBody\n└────────┘"],
      Toast: [Zaniah::UI::Toast.new("Saved"), "Saved"],
      CommandPalette: [Zaniah::UI::CommandPalette.new(ITEMS, open: true), "> \nOne\nTwo"],
      SplitPane: [Zaniah::UI::SplitPane.new(label["Left"], label["Right"]), "Left │ Right"],
      Resizable: [Zaniah::UI::Resizable.new(label["Body"]), "┌────────┐\nBody\n└───────┘↘"],
      DockPanel: [Zaniah::UI::DockPanel.new(center: label["Center"], top: label["Top"], left: label["Left"], bottom: label["Bottom"]), "Top\nLeft | Center\nBottom"],
      ListView: [Zaniah::UI::ListView.new(%w[Alpha Beta], selected: 1), "  Alpha\n> Beta"],
      Table: [Zaniah::UI::Table.new(ROWS, columns: COLUMNS), "ID | Name\n1 | Alpha\n2 | Beta"],
      DataGrid: [Zaniah::UI::DataGrid.new(ROWS, columns: COLUMNS), "ID | Name\n1 | Alpha\n2 | Beta"],
      TreeView: [Zaniah::UI::TreeView.new([{id: :root, label: "Root", children: ["Leaf"]}]), "▸ Root"],
      Sparkline: [Zaniah::UI::Sparkline.new([1, 4, 2]), "▁█▃"],
      LineChart: [Zaniah::UI::LineChart.new({A: [1, 4, 2]}), "▁█▃"], BarChart: [Zaniah::UI::BarChart.new({A: [1, 4, 2]}), "▁█▃"],
      FormField: [Zaniah::UI::FormField.new(:name, value: "Ada", label: "Name"), "Name: Ada"],
      Form: [Zaniah::UI::Form.new.field(name: :name, value: "Ada", label: "Name"), "Name: Ada\n[Submit]"],
      CodeEditor: [Zaniah::UI::CodeEditor.new("puts :ok\n"), "   1  puts :ok"],
      RichText: [Zaniah::UI::RichText.new(["Rich ", {text: "text"}]), "Rich text"]
    }
  end

  def test_every_public_component_has_a_stable_text_snapshot
    cases.each do |name, (component, expected)|
      assert_equal expected, component.tui_cells, name.to_s
    end
  end
end
