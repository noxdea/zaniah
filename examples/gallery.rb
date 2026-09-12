# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah/ui"

module Gallery
  module_function

  def section(title, *children)
    Zaniah::UI::Card.new(Zaniah::UI::Label.new(title, size: :lg),
      Zaniah::Div.new.flex_row.style(flex_wrap: :wrap).gap(10).children(children.flatten.compact))
  end

  def page
    clicks = ->(*) {}
    tabs = Zaniah::UI::Tabs.new([["Overview", Zaniah::UI::Label.new("Overview panel")], ["Details", Zaniah::UI::Label.new("Details panel")]])
    Zaniah::Div.new.h(1700).p(16).gap(12)
      .child(section("Foundation",
        Zaniah::UI::Label.new("Label"), Zaniah::UI::Icon.new(:info, label: "Information"),
        Zaniah::UI::Divider.new, Zaniah::UI::Spacer.new(8), Zaniah::UI::Badge.new("New", variant: :accent),
        Zaniah::UI::Avatar.new("Ruby UI"), Zaniah::UI::Skeleton.new,
        Zaniah::UI::EmptyState.new("No results", message: "Try another query")))
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
      .child(section("Structure", tabs,
        Zaniah::UI::Accordion.new([["Section one", Zaniah::UI::Label.new("Content")], ["Section two", Zaniah::UI::Label.new("More")]]),
        Zaniah::UI::Collapsible.new("Disclosure", Zaniah::UI::Label.new("Visible"), open: true),
        Zaniah::UI::Toolbar.new(Zaniah::UI::Button.new("New", size: :sm), Zaniah::UI::Button.new("Edit", size: :sm)),
        Zaniah::UI::StatusBar.new(Zaniah::UI::Label.new("Ready", size: :sm)),
        Zaniah::UI::Sidebar.new(Zaniah::UI::Label.new("Navigation"), width: 160).h(100)))
  end

  def overlay(name, window)
    anchor = Zaniah::Bounds.new(280, 80, 80, 32)
    content = Zaniah::UI::Label.new("Overlay content")
    items = [["First command", ->(*) {}], ["Unavailable", nil], ["Close", ->(*) {}]]
    case name
    when "tooltip" then Zaniah::UI::Tooltip.new("Helpful text", anchor: anchor)
    when "popover" then Zaniah::UI::Popover.new(content, anchor: anchor)
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

backend_option = ARGV.find { |argument| argument.start_with?("--backend=") }&.split("=", 2)&.last || "headless"
backend = if backend_option == "native"
  RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mingw|mswin/) ? :windows : :linux
else
  backend_option.to_sym
end
window = Zaniah::Platform.open_window(backend: backend, width: 900, height: 700, title: "Zaniah component gallery")
unless backend == :tui
  require "alhena"
  font_path = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)
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
  puts "gallery: #{backend} rendered #{window.scene.commands.length} scene commands"
  window.close
else
  window.run
end
