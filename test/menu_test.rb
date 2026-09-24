# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"

class MenuTest < Minitest::Test
  def setup
    @app = Zaniah::App.new
    @keymap = Zaniah::Input::Keymap.new.bind("enter", :activate).bind("ctrl-s", :save)
      .bind("ctrl-k ctrl-s", :save_all)
      .bind("ctrl-x", :cut, context: "in_text_field")
    @window = @app.open_window(backend: :headless, width: 360, height: 240, keymap: @keymap)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_menu_dsl_resolves_titles_shortcuts_and_dynamic_children_on_open
    calls = 0
    @app.actions.register(:save, title: "Save file") { }
    menu = Zaniah::Menu.build do
      app_menu
      submenu "File" do
        item :save
        separator
        submenu "Recent", items: -> { calls += 1; Zaniah::Menu.build { item :save_all, title: "Save all" } }
      end
      window_menu
    end
    @app.menu_bar = menu
    @window.render(Zaniah::Div.new, present: false)

    assert_same menu, Zaniah::Inspection.snapshot(@window).overlays.menu
    top = menu.resolve(registry: @app.actions, keymap: @keymap, platform: :linux)
    assert_equal ["File"], top.map(&:title)
    file = menu.children_for(top.first, registry: @app.actions, keymap: @keymap)
    assert_equal ["Save file", nil, "Recent"], file.map(&:title)
    assert_equal "ctrl-s", file.first.shortcut
    assert_equal "ctrl-s", @keymap.shortcut_for("save")
    assert_equal 0, calls
    recent = menu.children_for(file.last, registry: @app.actions, keymap: @keymap)
    assert_equal ["Save all"], recent.map(&:title)
    assert_equal "ctrl-k ctrl-s", recent.first.shortcut
    assert_equal 1, calls
  end

  def test_dynamic_items_can_use_the_callers_methods
    menu = Zaniah::Menu.build do
      submenu "Recent", items: -> { recent_menu_items }
    end
    children = menu.children_for(menu.items.first)
    assert_equal [:save], children.map(&:action)
  end

  def test_keymap_shortcut_prefers_latest_unconditional_binding
    @keymap.bind("alt-s", :save, context: "in_text_field")
    @keymap.bind("shift-ctrl-s", :save)
    assert_equal "ctrl-shift-s", @keymap.shortcut_for(:save)
    assert_nil @keymap.shortcut_for(:cut)
  end

  def test_kbd_uses_platform_notation_and_tui_text
    mac = Zaniah::UI::Kbd.new("cmd-shift-p", platform: :mac)
    windows = Zaniah::UI::Kbd.new("ctrl-k ctrl-s", platform: :windows)
    assert_equal "Ctrl+K Ctrl+S", windows.tui_cells
    assert_equal "Ctrl+K Ctrl+S", windows.accessibility_node(nil).label
    assert_equal "Super+Shift+P", mac.tui_cells
    assert_equal "⌘⇧P", mac.send(:display)
    assert_equal "ctrl-s", Zaniah::UI::Kbd.for(:save, keymap: @keymap).keys.join(" ")
  end

  def test_model_menu_bar_dispatches_and_checks_commands
    called = []
    @app.actions.register(:save, title: "Save", checked: ->(_cx) { true }) { called << :save }
    @app.actions.register(:blocked, title: "Blocked", enabled: ->(_cx) { false }) { called << :blocked }
    @app.menu_bar = Zaniah::Menu.build do
      submenu "File" do
        item :save
        item :blocked
      end
    end
    bar = Zaniah::UI::MenuBar.from(@app.menu_bar)
    @window.draw { bar }
    @window.tick
    button_bounds = bar.root.children.first.layout_node.bounds
    position = Zaniah::Point.new(button_bounds.x + 5, button_bounds.y + 5)
    @window.input(Zaniah::Input::MouseDown.new(position, :left, [], 1))
    @window.input(Zaniah::Input::MouseUp.new(position, :left, []))
    @window.tick

    menu = bar.accessibility_node(nil).children.last
    assert_equal :menu, menu.role
    assert_equal [true, false], menu.children.map { |item| item.states[:checked] || !item.states[:disabled] }
    assert_equal true, menu.children.first.states[:checked]
    assert_equal true, menu.children.last.states[:disabled]
    @window.input(Zaniah::Input::KeyDown.new("enter", false))
    assert_equal [:save], called
    assert_nil @window.popup
  end

  def test_legacy_array_menus_still_work
    items = [["Run", -> { }], ["Disabled", nil]]
    assert_equal "> Run\n  Disabled", Zaniah::UI::Menu.new(items).tui_cells
    assert_equal "File", Zaniah::UI::MenuBar.new([["File", items]]).tui_cells
  end

  def test_context_menu_accepts_model_and_runs_nested_enabled_action
    called = []
    @keymap.bind("down", :next_option, context: "in_menu")
    @app.actions.register(:save, title: "Save file") { called << :save }
    @app.actions.register(:blocked, title: "Blocked", enabled: ->(_cx) { false }) { called << :blocked }
    menu = Zaniah::Menu.build do
      item :blocked
      separator
      submenu "More" do
        item :save
      end
    end
    @window.draw { Zaniah::Div.new.context_menu(menu) }
    @window.tick
    assert_equal [["Blocked", false], ["", false], ["More", true]],
      Zaniah::Inspection.snapshot(@window).root.context_menu
    @window.context_menu(menu, position: Zaniah::Point.new(10, 10))
    @window.tick

    assert_equal ["Blocked", "────────", "More"], @window.popup.labels
    assert_equal [false, false, true], @window.popup.enabled
    @window.input(Zaniah::Input::KeyDown.new("enter", false))
    @window.tick
    assert_equal ["← Back", "Save file"], @window.popup.labels
    @window.input(Zaniah::Input::KeyDown.new("down", false))
    @window.input(Zaniah::Input::KeyDown.new("enter", false))
    assert_equal [:save], called
  end

  def test_command_palette_from_registry_shows_keymap_shortcut
    @app.actions.register(:save, title: "Save") { }
    palette = Zaniah::UI::CommandPalette.from(@app.actions, open: true, keymap: @keymap)
    @window.render(palette, present: false)

    assert_includes palette.tui_cells, "Save  Ctrl+S"
    assert Zaniah::Inspection.snapshot(@window).where(type: Zaniah::UI::Kbd).any?
  end

  def test_nested_menu_evaluates_dynamic_items_when_opened
    @keymap.bind("down", :next_option, context: "in_menu")
    opened = 0
    called = []
    @app.actions.register(:save, title: "Save") { called << :save }
    @app.actions.register(:save_all, title: "Save all") { called << :save_all }
    @app.menu_bar = Zaniah::Menu.build do
      submenu "File" do
        item :save
        separator
        submenu "Recent", items: -> { opened += 1; Zaniah::Menu.build { item :save_all } }
      end
    end
    bar = Zaniah::UI::MenuBar.from(@app.menu_bar)
    @window.draw { bar }
    @window.tick
    button_bounds = bar.root.children.first.layout_node.bounds
    position = Zaniah::Point.new(button_bounds.x + 5, button_bounds.y + 5)
    @window.input(Zaniah::Input::MouseDown.new(position, :left, [], 1))
    @window.input(Zaniah::Input::MouseUp.new(position, :left, []))
    @window.tick
    assert_equal 0, opened

    @window.input(Zaniah::Input::KeyDown.new("down", false))
    @window.input(Zaniah::Input::KeyDown.new("enter", false))
    @window.tick
    assert_equal 1, opened
    assert_equal ["← Back", "Save all"], bar.accessibility_node(nil).children.last.children.map(&:label)
    @window.input(Zaniah::Input::KeyDown.new("down", false))
    @window.input(Zaniah::Input::KeyDown.new("enter", false))
    assert_equal [:save_all], called
  end

  def test_edit_menu_uses_the_focus_that_was_active_before_menu_opened
    called = []
    field = Zaniah::Div.new.h(30).focusable(context: {in_text_field: true},
      validate: ->(action) { action == :copy ? true : nil }) { |action| called << action; action == :copy }
    @app.menu_bar = Zaniah::Menu.build { submenu("Edit") { item :copy } }
    bar = Zaniah::UI::MenuBar.from(@app.menu_bar)
    @window.draw { Zaniah::Div.new.gap(4).child(bar).child(field) }
    @window.tick
    @window.dispatcher.focus(field.focus_handle)
    button_bounds = bar.root.children.first.layout_node.bounds
    position = Zaniah::Point.new(button_bounds.x + 5, button_bounds.y + 5)
    @window.input(Zaniah::Input::MouseDown.new(position, :left, [], 1))
    @window.input(Zaniah::Input::MouseUp.new(position, :left, []))
    @window.tick

    menu = bar.accessibility_node(nil).children.last
    assert_equal false, menu.children.first.states[:disabled]
    @window.input(Zaniah::Input::KeyDown.new("enter", false))
    assert_equal [:copy], called
    assert_same field.focus_handle, @window.dispatcher.focused
  end

  def test_edit_menu_targets_the_current_text_field_after_rerender
    field = Zaniah::UI::TextField.new("alpha")
    @app.menu_bar = Zaniah::Menu.build { submenu("Edit") { item :select_all } }
    bar = Zaniah::UI::MenuBar.from(@app.menu_bar)
    @window.draw { Zaniah::Div.new.gap(4).child(bar).child(field) }
    @window.tick
    original = field.focus_handle
    @window.dispatcher.focus(original)
    button_bounds = bar.root.children.first.layout_node.bounds
    position = Zaniah::Point.new(button_bounds.x + 5, button_bounds.y + 5)
    @window.input(Zaniah::Input::MouseDown.new(position, :left, [], 1))
    @window.input(Zaniah::Input::MouseUp.new(position, :left, []))
    @window.tick

    refute_same original, field.focus_handle
    assert_equal true, @window.dispatcher.focused.context[:in_menu]
    @window.input(Zaniah::Input::KeyDown.new("enter", false))
    assert_equal 0...5, field.focus_handle.owner.selection.range
    assert_same field.focus_handle, @window.dispatcher.focused
  end

  def test_menu_bar_accessibility_uses_resolved_registry_titles
    @app.actions.register(:save, title: "Save document") { }
    @app.menu_bar = Zaniah::Menu.build { item :save }
    bar = Zaniah::UI::MenuBar.from(@app.menu_bar)
    @window.draw { bar }
    @window.tick

    assert_equal "Save document", bar.accessibility_node(nil).children.first.label
    assert_equal "Save document", @window.accessibility_tree.query(role: :menuitem).first.first.label
  end

  private

  def recent_menu_items = Zaniah::Menu.build { item :save }
end
