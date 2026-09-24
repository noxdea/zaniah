# frozen_string_literal: true

require_relative "test_helper"

if RUBY_PLATFORM.include?("darwin")
  require "zaniah/platform/mac"

  class MacNativeMenuTest < Minitest::Test
    O = Zaniah::Platform::Mac::O

    def setup
      @pool = O.new("NSAutoreleasePool")
      @host = Zaniah::Platform::Mac::App.instance
      @previous_menu = @host.instance_variable_get(:@native_menu)
      @app = Zaniah::App.new
      @window = @app.open_window(backend: :headless)
      @window.define_singleton_method(:handle) { 0 }
      @window.dispatcher.keymap.bind("cmd-shift-s", :save)
    end

    def teardown
      @host&.instance_variable_set(:@native_menu, @previous_menu)
      @native&.release
      @window&.close
      O.release(@pool) if @pool
    end

    def test_commands_shortcuts_validation_and_dynamic_submenus
      calls = []
      @app.actions.register(:save, title: "Save File", enabled: ->(_cx) { @enabled }) { |_cx| calls << :save }
      @app.actions.register(:toggle, title: "Toggle", checked: ->(_cx) { @checked }) { |_cx| calls << :toggle }
      @enabled, @checked, opens = true, true, []
      model = Zaniah::Menu.build do
        app_menu
        submenu "File" do
          item :save
          separator
          submenu "Recent", items: -> { opens << true; Zaniah::Menu.build { item :toggle }.items }
        end
        window_menu
      end
      @native = Zaniah::Platform::Mac::NativeMenu.new(@host, model, @window)
      @host.instance_variable_set(:@native_menu, @native)
      assert_equal 3, O.send(@native.root, "numberOfItems", result: :long)
      file = submenu(@native.root, 1)
      save = native_item(file, 0)
      assert_equal "Save File", O.text(O.send(save, "title"))
      assert_equal "s", O.text(O.send(save, "keyEquivalent"))
      assert_equal (1 << 20) | (1 << 17), O.send(save, "keyEquivalentModifierMask", result: :ulong)
      O.send(@host.delegate, "menuNeedsUpdate:", file, args: [:pointer], result: :void)
      assert_equal 1, O.send(save, "isEnabled", result: :bool)
      assert_equal 1, O.send(@host.delegate, "validateMenuItem:", save, args: [:pointer], result: :bool)
      O.send(@host.delegate, "zaniahMenuAction:", save, args: [:pointer], result: :void)
      assert_equal [:save], calls
      @enabled = false
      O.send(@host.delegate, "menuNeedsUpdate:", file, args: [:pointer], result: :void)
      assert_equal 0, O.send(save, "isEnabled", result: :bool)
      assert_equal 0, O.send(@host.delegate, "validateMenuItem:", save, args: [:pointer], result: :bool)
      refute @native.perform(-1)
      assert_empty opens

      recent = submenu(file, 2)
      @native.update(recent)
      assert_equal 1, opens.length
      toggle = native_item(recent, 0)
      assert_equal 1, O.send(toggle, "state", result: :long)
      old_tag = O.send(toggle, "tag", result: :long)
      @native.update(recent)
      assert_equal 2, opens.length
      assert_equal 1, O.send(recent, "numberOfItems", result: :long)
      refute @native.perform(old_tag)
      assert @native.perform(O.send(native_item(recent, 0), "tag", result: :long))
      assert_equal [:save, :toggle], calls
      assert_equal @native.windows_menu, submenu(@native.root, 2)
    end

    def test_key_equivalent_omits_chords_and_uses_cocoa_special_keys
      keys = Zaniah::Platform::Mac::NativeMenu
      assert_equal ["", 0], keys.key_equivalent("cmd-k cmd-s")
      assert_equal ["\uF700", 1 << 20], keys.key_equivalent("cmd-up")
      assert_equal ["\b", 1 << 20], keys.key_equivalent("cmd-backspace")
      assert_equal ["-", 1 << 20], keys.key_equivalent("cmd--")
      assert_equal ["", 0], keys.key_equivalent("cmd-unknown")
    end

    def test_view_key_equivalent_uses_the_dispatcher_once
      calls = 0
      @app.actions.register(:save) { |_cx| calls += 1 }
      @window.dispatcher.keymap.bind("cmd-s", :save)
      view_window = Zaniah::Platform::Mac::Window.allocate
      view_window.instance_variable_set(:@dispatcher, @window.dispatcher)
      char = O.string("s")
      event = O.send(O.klass("NSEvent"),
        "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:",
        10, [0, 0], 1 << 20, 0.0, 0, 0, char, char, 0, 1,
        args: [:ulong, :point, :ulong, :double, :long, :pointer, :pointer, :pointer, :bool, :uint])
      assert view_window.perform_key_equivalent(event)
      assert_equal 1, calls
    end

    def test_context_menu_model_builds_native_submenu_and_routes_enabled_action
      called = []
      @app.actions.register(:save, title: "Save") { called << :save }
      @app.actions.register(:blocked, title: "Blocked", enabled: ->(_cx) { false }) { called << :blocked }
      model = Zaniah::Menu.build do
        item :blocked
        separator
        submenu "More" do
          item :save
        end
      end
      context = Zaniah::Platform::Mac::Window.allocate
      context.app = @app
      context.instance_variable_set(:@dispatcher, @window.dispatcher)
      context.instance_variable_set(:@context_actions, [])
      native = O.new("NSMenu")
      options = {registry: @app.actions, keymap: @window.dispatcher.keymap, platform: :mac}
      context.append_context_model_items(native, model, model.resolve(**options), options)

      assert_equal 3, O.send(native, "numberOfItems", result: :long)
      assert_equal 0, O.send(native_item(native, 0), "isEnabled", result: :bool)
      assert_equal 1, O.send(native_item(native, 1), "isSeparatorItem", result: :bool)
      nested = submenu(native, 2)
      assert_equal "Save", O.text(O.send(native_item(nested, 0), "title"))
      context.context_action(1)
      assert_equal [:save], called
    ensure
      O.release(native) if native
    end

    def test_native_callback_error_is_reported_once
      @host.native_callback { raise "menu callback failed" }
      assert_equal "menu callback failed", assert_raises(RuntimeError) { @host.poll }.message
      @host.poll
    end

    private

    def native_item(menu, index) = O.send(menu, "itemAtIndex:", index, args: [:long])
    def submenu(menu, index) = O.send(native_item(menu, index), "submenu")
  end
end
