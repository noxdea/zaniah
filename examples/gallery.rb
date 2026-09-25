# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah/ui"

module Gallery
  module_function

  def section(title, *children, height: nil)
    card = Zaniah::UI::Card.new(Zaniah::UI::Label.new(title, size: :lg),
      Zaniah::Div.new.flex_row.style(flex_wrap: :wrap).gap(10).children(children.flatten.compact))
    card.h(height) if height
    card
  end

  def page
    clicks = ->(*) {}
    tabs = Zaniah::UI::Tabs.new([["Overview", Zaniah::UI::Label.new("Overview panel")], ["Details", Zaniah::UI::Label.new("Details panel")]]).w(220)
    rows = Array.new(40) { |index| {id: index + 1, name: "Record #{index + 1}", status: index.even? ? "Ready" : "Queued"} }
    validation = Zaniah::UI::Validation.new.required.format(/@/, message: "Enter an email address")
    foundation = Zaniah::Div.new.w_full.gap(8)
      .child(Zaniah::Div.new.flex_row.items_center.gap(12).children([
        Zaniah::UI::Label.new("Label"), Zaniah::UI::Icon.new(:info, label: "Information"),
        Zaniah::UI::Badge.new("New", variant: :accent), Zaniah::UI::Avatar.new("Ruby UI"),
        Zaniah::UI::Kbd.new("ctrl-shift-p", platform: :windows),
        Zaniah::UI::Spacer.new(4), Zaniah::UI::Skeleton.new]))
      .child(Zaniah::UI::Divider.new)
      .child(Zaniah::UI::EmptyState.new("No results", message: "Try another query").h(64))
    button_variants = %i[primary secondary ghost danger].map do |variant|
      Zaniah::Div.new.flex_row.gap(8).children(%i[sm md lg].map { |size| Zaniah::UI::Button.new("#{variant} #{size}", variant: variant, size: size) })
    end
    variants = Zaniah::Div.new.w_full.gap(8).children(button_variants)
      .child(Zaniah::Div.new.flex_row.gap(8).children(%i[neutral accent success warning danger].map { |variant| Zaniah::UI::Badge.new(variant, variant: variant) }))
      .child(Zaniah::Div.new.flex_row.gap(14).children(%i[default muted].map { |tone| Zaniah::UI::Label.new(tone, tone: tone) }))
      .child(Zaniah::Div.new.flex_row.items_center.gap(14).children(%i[xs sm md lg xl].map { |size| Zaniah::UI::Label.new(size, size: size) }))
    structure = Zaniah::Div.new.w_full.gap(10)
      .child(Zaniah::Div.new.flex_row.gap(12).children([tabs,
        Zaniah::UI::Accordion.new([["Section one", Zaniah::UI::Label.new("Content")], ["Section two", Zaniah::UI::Label.new("More")]]).w(240),
        Zaniah::UI::Collapsible.new("Disclosure", Zaniah::UI::Label.new("Visible"), open: true).w(210),
        Zaniah::UI::Sidebar.new(Zaniah::UI::Label.new("Sidebar", size: :sm), width: 100).h(80)]))
      .child(Zaniah::UI::Toolbar.new(Zaniah::UI::Button.new("New", size: :sm), Zaniah::UI::Button.new("Edit", size: :sm)))
      .child(Zaniah::UI::StatusBar.new(Zaniah::UI::Label.new("Ready", size: :sm)))
    data = Zaniah::Div.new.w_full.gap(12)
      .child(Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::Table.new(rows.first(8), columns: [{key: :id, width: 54}, {key: :name, width: 136}], height: 190, row_key: ->(row) { row[:id] }).w(200),
        Zaniah::UI::DataGrid.new(rows, columns: [{key: :id, width: 54}, {key: :name, width: 130, editable: true}, {key: :status, width: 90}], height: 190, row_key: ->(row) { row[:id] }).w(285),
        Zaniah::UI::TreeView.new([{id: :src, label: "lib", children: [{id: :core, label: "zaniah.rb"}, {id: :ui, label: "ui", children: ["controls.rb", "data.rb"]}]}], height: 190).w(240)]))
      .child(Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::Sparkline.new([2, 5, 3, 8, 6, 9], width: 190, height: 120, label: "Frames"),
        Zaniah::UI::LineChart.new({Frames: [2, 5, 3, 8, 6, 9], Input: [1, 2, 2, 4, 3, 5]}, width: 300, height: 150),
        Zaniah::UI::BarChart.new({GPU: [4, 7, 6], TUI: [3, 4, 5]}, width: 300, height: 150)]))
    choices = Zaniah::Div.new.w_full.gap(10)
      .child(Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::Select.new([["Ruby", :ruby], ["Zig", :zig]], value: :ruby),
        Zaniah::UI::Combobox.new(%w[Ruby Zig Rust], value: "Ruby", label: "Language"),
        Zaniah::UI::MultiSelect.new(%w[GPU TUI A11y], value: %w[GPU A11y], label: "Targets")]))
      .child(Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::DatePicker.new("2026-09-13"), Zaniah::UI::TimePicker.new("14:30"),
        Zaniah::UI::ColorPicker.new("#2563eb")]))
    feedback_dates = Zaniah::Div.new.w_full.gap(12)
      .child(Zaniah::Div.new.flex_row.items_center.gap(16).children([
        Zaniah::UI::SegmentedControl.new([["Day", :day], ["Week", :week], ["Month", :month]], value: :week),
        Zaniah::UI::DateRangePicker.new(value: ["2026-09-01", "2026-09-30"])]))
      .child(Zaniah::UI::Alert.new("Export complete", message: "Your file is ready", variant: :success, dismissible: true))
      .child(Zaniah::UI::Calendar.new(value: "2026-09-24", week_start: 1))
    dock_layout = Zaniah::UI::DockLayout.split(id: :work, orientation: :horizontal, ratio: 0.42,
      first: Zaniah::UI::DockLayout.tabs(id: :left, panels: %i[Files Search]),
      second: Zaniah::UI::DockLayout.tabs(id: :right, panels: %i[Editor Preview]))
    property_schema = [
      {key: :title, label: "Title", type: :text},
      {key: :count, label: "Count", type: :number},
      {key: :visible, label: "Visible", type: :boolean}
    ]
    workspaces = Zaniah::Div.new.w_full.gap(12)
      .child(Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::SplitPane.new(Zaniah::UI::Label.new("Left pane"), Zaniah::UI::Label.new("Right pane")).w(300).h(100),
        Zaniah::UI::Resizable.new(Zaniah::UI::Label.new("Resize me"), width: 180, height: 100),
        Zaniah::UI::ListView.new(%w[Alpha Beta Gamma], height: 100, selected: 1).w(180)]))
      .child(Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::DockPanel.new(
          center: Zaniah::UI::Label.new("Editor"), top: Zaniah::UI::StatusBar.new(Zaniah::UI::Label.new("Top", size: :sm)),
          left: Zaniah::UI::Sidebar.new(Zaniah::UI::Label.new("Files", size: :sm), width: 90),
          bottom: Zaniah::UI::StatusBar.new(Zaniah::UI::Label.new("Ready", size: :sm))).w(420).h(120),
        Zaniah::UI::ZoomPanView.new(Zaniah::Div.new.w(110).h(70).p(8).bg("#2563eb")
          .child(Zaniah::UI::Label.new("Zoom / pan", size: :sm)), zoom: 1).w(180).h(120)
      ]))
      .child(Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::DockWorkspace.new(dock_layout,
          render: ->(id) { Zaniah::Div.new.p(10).child(Zaniah::UI::Label.new("#{id} panel")) }).w(440).h(190),
        Zaniah::UI::PropertyGrid.new(property_schema,
          {title: "Workspace", count: 3, visible: true}, height: 190).w(340)
      ]))
    editors = Zaniah::Div.new.w_full.flex_row.gap(12).children([
      Zaniah::UI::CodeEditor.new("def hello\n  :world\nend\n", language: :ruby).w(390).h(150),
      Zaniah::UI::RichText.new([{text: "Rich ", size: 20}, {text: "text", color: "#2563eb", size: 20}]).w(260)])
    Zaniah::Div.new.h(3200).p(16).gap(12)
      .child(section("Foundation", foundation, height: 180))
      .child(section("Actions",
        Zaniah::UI::Button.new("Primary").icon(:check).on_click(&clicks),
        Zaniah::UI::IconButton.new(:menu, label: "Menu", variant: :secondary),
        Zaniah::UI::ToggleButton.new("Toggle"),
        Zaniah::UI::ButtonGroup.new(Zaniah::UI::Button.new("One", size: :sm), Zaniah::UI::Button.new("Two", size: :sm)),
        Zaniah::UI::Checkbox.new("Mixed", value: :mixed), Zaniah::UI::Radio.new("Radio", value: true),
        Zaniah::UI::RadioGroup.new([["A", :a], ["B", :b]], value: :a), Zaniah::UI::Switch.new("Switch", value: true)))
      .child(section("Values",
        Zaniah::UI::Slider.new(value: 35, label: "Slider"), Zaniah::UI::RangeSlider.new(value: [20, 80], label: "Range"),
        Zaniah::UI::ProgressBar.new(value: 60), Zaniah::UI::Spinner.new, Zaniah::UI::Meter.new(value: 72, low: 25, high: 80)))
      .child(section("Text input",
        Zaniah::UI::TextField.new("Ruby", label: "Text field", clearable: true),
        Zaniah::UI::TextArea.new("Multiple\nlines", label: "Text area", rows: 3),
        Zaniah::UI::SearchInput.new("", placeholder: "Search"), Zaniah::UI::PasswordInput.new("secret", label: "Password"),
        Zaniah::UI::NumberInput.new(4, min: 0, max: 10), Zaniah::UI::TagInput.new(%w[ruby ui], placeholder: "Tags")))
      .child(section("Navigation",
        Zaniah::UI::MenuBar.new([["File", [["Open", clicks], ["Disabled", nil]]]]),
        Zaniah::UI::Dropdown.new("Choose", items: [["First", 1], ["Second", 2]]),
        Zaniah::UI::Breadcrumb.new([["Home", clicks], ["Gallery", nil]]), Zaniah::UI::Pagination.new(page: 4, pages: 12)))
      .child(section("Structure", structure, height: 235))
      .child(section("Variants", variants, height: 285))
      .child(section("Data", data, height: 440))
      .child(section("Choice and pickers", choices, height: 210))
      .child(section("Feedback and dates", feedback_dates, height: 410))
      .child(section("Workspace layout", workspaces, height: 530))
      .child(section("Editors", editors, height: 210))
      .child(section("Forms", Zaniah::UI::Form.new.field(name: :email, label: "Release email", value: "ruby@example.com", validation: validation).w(320), height: 150))
  end

  def overlay(name, window)
    anchor = Zaniah::Bounds.new(280, 80, 80, 32)
    content = Zaniah::UI::Label.new("Overlay content")
    items = [["First command", ->(*) {}], ["Unavailable", nil], ["Close", ->(*) {}]]
    case name
    when /\Atooltip-(top|bottom|left|right)\z/ then Zaniah::UI::Tooltip.new("Helpful text", anchor: anchor, side: Regexp.last_match(1).to_sym)
    when /\Apopover-(top|bottom|left|right)\z/ then Zaniah::UI::Popover.new(content, anchor: anchor, side: Regexp.last_match(1).to_sym)
    when /\Adrawer-(left|right)\z/ then Zaniah::UI::Drawer.new(content, title: "Drawer", side: Regexp.last_match(1).to_sym)
    when /\Atoast-(info|success|warning|danger)\z/ then Zaniah::UI::Toast.new("Saved", variant: Regexp.last_match(1).to_sym)
    when "tooltip" then Zaniah::UI::Tooltip.new("Helpful text", anchor: anchor)
    when "popover" then Zaniah::UI::Popover.new(content, anchor: anchor)
    when "hover-card" then Zaniah::UI::HoverCard.new(Zaniah::UI::Label.new("Keyboard shortcuts"), anchor: anchor).open
    when "menu" then Zaniah::UI::Menu.new(items, anchor: Zaniah::Point.new(anchor.x, anchor.bottom))
    when "context-menu" then Zaniah::UI::ContextMenu.new(items, anchor: Zaniah::Point.new(anchor.x, anchor.bottom))
    when "modal" then Zaniah::UI::Modal.new(content, title: "Modal")
    when "dialog" then Zaniah::UI::Dialog.new(content, title: "Dialog")
    when "drawer" then Zaniah::UI::Drawer.new(content, title: "Drawer")
    when "toast" then Zaniah::UI::Toast.new("Saved", variant: :success)
    when "command-palette" then Zaniah::UI::CommandPalette.new(items, open: true)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  backend_option = ARGV.find { |argument| argument.start_with?("--backend=") }&.split("=", 2)&.last || "headless"
  backend = if backend_option == "native"
    RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mingw|mswin/) ? :windows : :linux
  else
    backend_option.to_sym
  end
  window = Zaniah::Platform.open_window(backend: backend, width: 900, height: 700, title: "Zaniah component gallery")
  unless backend == :tui
    require "alhena"
    font_path = File.expand_path("../assets/fonts/NotoSans-Regular.ttf", __dir__)
    window.text_system = Zaniah::TextSystem::Renderer.new(font: Alhena::Font.open(font_path), font_db: Zaniah::TextSystem::FontDB.new(paths: []))
  end
  overlay_name = ARGV.find { |argument| argument.start_with?("--overlay=") }&.split("=", 2)&.last
  scroll = Zaniah::ScrollView.new(scrollbar: :overlay).child(Gallery.page)
  root = Zaniah::Div.new.child(scroll)
  root.child(Gallery.overlay(overlay_name, window)) if overlay_name
  window.draw { root }

  if ARGV.include?("--check")
    window.tick
    output = ARGV.find { |argument| argument.end_with?(".png") }
    window.write_png(output) if output && backend != :tui
    raise "gallery did not render" if window.scene.commands.empty?
    if !%i[headless tui].include?(backend) && (!window.device.respond_to?(:draw_calls) || !window.device.draw_calls&.positive?)
      raise "gallery produced no native GPU draw calls"
    end
    puts "gallery: #{backend} rendered #{window.scene.commands.length} scene commands"
    window.close
  else
    window.run
  end
end
