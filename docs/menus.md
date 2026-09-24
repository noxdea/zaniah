# Menus and shortcuts

`Zaniah::Menu` describes commands; the application owns what each command does.
Register actions once and attach a menu model to the app:

```ruby
app.actions.register(:save, title: "Save") { |cx| save_document(cx) }
app.menu_bar = Zaniah::Menu.build do
  app_menu
  submenu "File" do
    item :save
    separator
    submenu "Recent", items: -> { recent_items }
  end
  submenu "Edit" do
    standard_edit_items
  end
  window_menu
end
```

`recent_items` must return a `Zaniah::Menu` or an array of `Menu::Item` values.
The callback runs when that submenu opens, not when the menu bar is drawn.
`app_menu` and `window_menu` are macOS-only placeholders. They are omitted on
other platforms. A missing item title comes from `app.actions`; a missing
shortcut comes from the most recent keymap binding valid in an empty context.
Context-only bindings are not shown. Multi-stroke shortcuts appear in window
menus and `UI::Kbd`, but native menus show only single strokes.

For Linux, headless, and TUI, place `Zaniah::UI::MenuBar.from(app.menu_bar)` in
the application layout. Zaniah never inserts it automatically. Menu commands
use `dispatcher.perform(action, source: :menu)` and are enabled or checked by
`available?` and `checked?` when a menu opens. The in-window menu exposes a
Back row for nested submenus and restores the previously focused control so
standard editing commands target that control. `Inspection.snapshot(window).overlays.menu`
returns the app's current model. Existing `UI::MenuBar.new([[label, items]])`
and `UI::Menu.new([[label, callback]])` forms remain valid.

`UI::Kbd.new("cmd-shift-p", platform: :mac)` displays `⌘⇧P`; on Windows or
Linux it displays `Super+Shift+P`. `UI::Kbd.for(:save, keymap: keymap)` uses
the same binding as the menu. Its TUI text always uses readable names such as
`Ctrl+Shift+P`.

Windows attaches a native menu to each window. It refreshes enabled and checked
states when a menu opens and evaluates dynamic submenus at that time. Single-key
shortcuts appear after a tab in item labels; key input still runs only through
the Zaniah keymap, not a Win32 accelerator table. The menu model remains
available for inspection and in-window display on all backends; headless has
no system menu.

On macOS, `App#menu_bar` becomes the system main menu. The app menu uses native
About, Hide, Show All, and Quit items; `window_menu` uses the native Window menu.
Dynamic submenu callbacks run when that submenu opens. Enabled and checked
states are refreshed from the active window's dispatcher. Native shortcuts
display single-stroke keymap bindings and route key events through the keymap
before AppKit can run a matching menu item. A missing menu model keeps the
original Quit-only menu. Run `ruby examples/native_menu.rb` in a macOS graphical
session to inspect the native behavior.

`element.context_menu(Zaniah::Menu.build { item :save })` accepts the same
command model as the menu bar, including separators, nested submenus, dynamic
items, and current enabled/checked state. macOS and Windows use native context
menus for this model; headless, TUI, and `UI::ContextMenu` use the in-window
menu. The older `[["Save", -> { save }]]` form remains supported.
