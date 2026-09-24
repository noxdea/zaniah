# frozen_string_literal: true

# Run on macOS with a graphical session. Check File, Edit, Window, Cmd+S,
# disabled and checked items, and the Recent submenu after opening it twice.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah/ui"

raise "native_menu.rb requires macOS" unless RUBY_PLATFORM.include?("darwin")

app = Zaniah::App.new
count = 0
enabled = true
checked = false
window = nil
app.actions.register(:save, title: "Save", enabled: ->(_cx) { enabled }) do |_cx|
  count += 1
  puts "Save invoked #{count} time(s)"
  window.request_frame
end
app.actions.register(:toggle, title: "Checked item", checked: ->(_cx) { checked }) do |_cx|
  checked = !checked
  window.request_frame
end
app.actions.register(:enable_save, title: "Enable Save") do |_cx|
  enabled = !enabled
  puts "Save enabled: #{enabled}"
end
app.menu_bar = Zaniah::Menu.build do
  app_menu
  submenu "File" do
    item :save
    item :enable_save
    separator
    submenu "Recent", items: -> { Zaniah::Menu.build { item :save, title: "Example.txt" }.items }
  end
  submenu "Edit" do
    standard_edit_items
    separator
    item :toggle
  end
  window_menu
end
window = app.open_window(backend: :mac, width: 500, height: 180, title: "Zaniah native menu") do
  Zaniah::Div.new.p(24).child(Zaniah::UI::Label.new("Open File/Edit/Window; press Cmd+S. Saves: #{count}"))
end
window.dispatcher.keymap.bind("cmd-s", :save)
if ARGV.include?("--check")
  window.tick
  cocoa = Zaniah::Platform::Mac::O
  menu = cocoa.send(Zaniah::Platform::Mac::App.instance.handle, "mainMenu")
  count = cocoa.send(menu, "numberOfItems", result: :long)
  raise "native main menu was not installed (#{count} items)" unless count == 4
  app.menu_bar = nil
  window.tick
  fallback = cocoa.send(Zaniah::Platform::Mac::App.instance.handle, "mainMenu")
  raise "Quit-only menu was not restored" unless cocoa.send(fallback, "numberOfItems", result: :long) == 1
  puts "Native menu installed"
  window.close
else
  app.run
end
