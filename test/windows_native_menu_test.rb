# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/windows/native_menu"
require "zaniah/platform/windows/window"

class WindowsNativeMenuTest < Minitest::Test
  class FakeUser
    attr_reader :calls
    attr_accessor :selected

    def initialize
      @calls = []
      @next_handle = 1000
    end

    def fn(name, _arguments, _result)
      ->(*arguments) do
        @calls << [name, arguments]
        case name
        when :CreateMenu, :CreatePopupMenu
          @next_handle += 1
          Fiddle::Pointer.new(@next_handle)
        when :TrackPopupMenuEx then @selected || 1
        else 1
        end
      end
    end

    def calls_for(name) = @calls.filter { |call| call.first == name }.map(&:last)
  end

  WindowStub = Struct.new(:handle, :app, :dispatcher) do
    def wide(text) = text.to_s.encode("UTF-16LE").b + "\0\0".b
  end

  def setup
    @app = Zaniah::App.new
    keymap = Zaniah::Input::Keymap.new.bind("ctrl-s", :save).bind("ctrl-k ctrl-a", :save_all)
    @headless = @app.open_window(backend: :headless, keymap: keymap)
    @window = WindowStub.new(Fiddle::Pointer.new(2000), @app, @headless.dispatcher)
    @user = FakeUser.new
    @native = Zaniah::Platform::Windows::NativeMenu.new(@window, @user)
  end

  def teardown
    @native.close
    @headless.close
    @app.executor.shutdown
  end

  def test_builds_windows_menu_with_display_only_shortcuts_and_updates_state
    enabled = true
    checked = true
    @app.actions.register(:save, title: "Save", enabled: ->(_cx) { enabled }, checked: ->(_cx) { checked }) { }
    @app.actions.register(:save_all, title: "Save all") { }
    @app.menu_bar = Zaniah::Menu.build do
      app_menu
      submenu "File" do
        item :save
        item :save_all
        separator
      end
      window_menu
    end

    @native.sync(@app.menu_bar)
    labels = @user.calls_for(:AppendMenuW).filter_map { |_, _, _, text| decode(text) if text.is_a?(String) }
    assert_equal ["File", "Save\tCtrl+S", "Save all"], labels
    refute @user.calls.any? { |name, _| name == :CreateAcceleratorTableW }
    assert_operator @user.calls_for(:AppendMenuW)[1][2], :>=, 0x8000

    popup = popup_for("File")
    enabled = false
    assert @native.prepare(popup, 0)
    assert_equal [1, 0], @user.calls_for(:EnableMenuItem).map(&:last)
    assert_equal [8, 0], @user.calls_for(:CheckMenuItem).map(&:last)
    enabled = true
    checked = false
    assert @native.prepare(popup, 0)
    assert_equal [0, 0], @user.calls_for(:EnableMenuItem).last(2).map(&:last)
    assert_equal [0, 0], @user.calls_for(:CheckMenuItem).last(2).map(&:last)
  end

  def test_dynamic_submenu_rebuilds_on_each_open_and_routes_commands
    calls = []
    recent = [:first]
    opened = 0
    @app.actions.register(:first, title: "First") { calls << :first }
    @app.actions.register(:second, title: "Second") { calls << :second }
    @app.menu_bar = Zaniah::Menu.build do
      submenu "File" do
        submenu "Recent", items: -> { opened += 1; Zaniah::Menu.build { recent.each { |action| item(action) } } }
      end
    end

    @native.sync(@app.menu_bar)
    recent_menu = popup_for("Recent")
    assert_equal 0, opened
    native_window = Zaniah::Platform::Windows::Window.allocate
    native_window.instance_variable_set(:@native_menu, @native)
    assert_equal 0, native_window.message(0x0117, recent_menu, 0)
    assert_equal 1, opened
    first_id = @user.calls_for(:AppendMenuW).last[2]
    assert_equal 0, native_window.message(0x0111, first_id, 0)
    assert_equal [:first], calls
    refute @native.command(first_id, 1)
    refute @native.command(first_id | (1 << 16), 0)

    recent = [:second]
    assert @native.prepare(recent_menu, 0)
    assert_equal 2, opened
    second_id = @user.calls_for(:AppendMenuW).last[2]
    assert_operator @user.calls_for(:DeleteMenu).length, :>=, 2
    assert @native.command(second_id, 0)
    assert_equal [:first, :second], calls
  end

  def test_replacing_or_removing_model_detaches_and_destroys_native_menu
    @app.actions.register(:save, title: "Save") { }
    first = Zaniah::Menu.build { submenu("File") { item :save } }
    second = Zaniah::Menu.build { submenu("Edit") { item :save } }
    @native.sync(first)
    @native.sync(second)
    @native.sync(nil)
    assert_equal 2, @user.calls_for(:DestroyMenu).length
    assert_equal 4, @user.calls_for(:SetMenu).length
  end

  def test_top_level_item_is_validated_when_root_menu_activates
    @app.actions.register(:save, title: "Save", enabled: ->(_cx) { false }) { }
    @native.sync(Zaniah::Menu.build { item :save })
    root = @user.calls_for(:SetMenu).last[1]
    native_window = Zaniah::Platform::Windows::Window.allocate
    native_window.instance_variable_set(:@native_menu, @native)
    assert_equal 0, native_window.message(0x0116, root, 0)
    assert_equal 1, @user.calls_for(:EnableMenuItem).last.last
  end

  def test_context_menu_model_uses_separate_ids_and_routes_nested_action
    called = []
    @app.actions.register(:blocked, title: "Blocked", enabled: ->(_cx) { false }) { called << :blocked }
    @app.actions.register(:save, title: "Save") { called << :save }
    menu = Zaniah::Menu.build do
      item :blocked
      separator
      submenu "More" do
        item :save
      end
    end
    native_window = Zaniah::Platform::Windows::Window.allocate
    native_window.app = @app
    native_window.instance_variable_set(:@handle, @window.handle)
    native_window.instance_variable_set(:@user, @user)
    native_window.instance_variable_set(:@dispatcher, @headless.dispatcher)
    native_window.instance_variable_set(:@scale_factor, 1.0)
    @user.selected = 2

    native_window.context_menu(menu, position: Zaniah::Point.new(10, 10))

    assert_equal [:save], called
    assert_equal 1, @user.calls_for(:DestroyMenu).length
    assert_equal 0, @user.calls_for(:AppendMenuW).first[1] & 0x0010
  end

  def test_custom_titlebar_hit_test_exposes_maximize_button_to_windows
    button = Zaniah::Div.new.w(24).h(24).window_control(:maximize)
    @headless.render(Zaniah::Div.new.w(100).h(40).window_drag_region.child(button), present: false)
    native_window = Zaniah::Platform::Windows::Window.allocate
    native_window.instance_variable_set(:@handle, @window.handle)
    native_window.instance_variable_set(:@user, @user)
    native_window.instance_variable_set(:@dispatcher, @headless.dispatcher)
    native_window.instance_variable_set(:@content_size, @headless.content_size)
    native_window.instance_variable_set(:@decorations, :none)
    native_window.instance_variable_set(:@resizable, true)
    native_window.instance_variable_set(:@scale_factor, 1.0)

    assert_equal 9, native_window.native_window_region(10 | (10 << 16))
    assert_equal 2, native_window.native_window_region(50 | (10 << 16))
    assert_equal 13, native_window.native_window_region(0)
  end

  private

  def decode(text) = text.force_encoding("UTF-16LE").encode("UTF-8").delete_suffix("\0")

  def popup_for(title)
    entry = @user.calls_for(:AppendMenuW).find { |_, _, _, text| text.is_a?(String) && decode(text) == title }
    Fiddle::Pointer.new(entry[2])
  end
end
