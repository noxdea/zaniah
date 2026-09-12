# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class NativeAccessibilityBridgesTest < Minitest::Test
  FakeDispatcher = Struct.new(:focused)
  FakeWindow = Struct.new(:handle, :scale_factor, :dispatcher)

  def test_native_tree_indexes_navigation_bounds_and_hit_testing
    child = Zaniah::Accessibility.node(role: :button, label: "Save", actions: [:press])
    root = Zaniah::Accessibility.node(role: :group, bounds: Zaniah::Bounds.new(10, 20, 100, 50), children: [child])
    tree = Zaniah::Accessibility::NativeTree.new(root)

    assert_same tree.root, tree[[].freeze]
    assert_same tree.root, tree.root.children.first.parent
    assert_equal root.bounds, tree.bounds(tree.root.children.first)
    assert_equal [0], tree.hit(Zaniah::Point.new(15, 25)).path
  end

  def test_windows_provider_exposes_fragment_navigation_roles_and_patterns
    child = Zaniah::Accessibility.node(role: :button, label: "Save", actions: [:press])
    root = Zaniah::Accessibility.node(role: :group, bounds: Zaniah::Bounds.new(0, 0, 100, 50), children: [child])
    bridge = Zaniah::Accessibility::Windows::Provider::Bridge.new(FakeWindow.new(1, 1, FakeDispatcher.new))
    bridge.update(root)
    provider = bridge.provider(bridge.tree.root.children.first)
    pointer = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
    variant = Fiddle::Pointer.malloc(16)

    assert_equal 0, provider.navigate(0, pointer)
    assert_equal bridge.root_provider.pointer(:fragment), pointer[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
    assert_equal 0, provider.property(30_003, variant)
    assert_equal 3, variant[0, 2].unpack1("v")
    assert_equal 50_000, variant[8, 4].unpack1("l")
    assert_equal 0, provider.pattern(10_000, pointer)
    assert_equal provider.pointer(:invoke), pointer[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
  end

  def test_native_action_routes_back_through_the_rendered_control
    app = Zaniah::App.new
    window = app.open_window(width: 120, height: 60)
    presses = 0
    window.draw { Zaniah::UI::Button.new("Save").on_click { presses += 1 } }
    window.tick

    node = window.accessibility_tree.root
    assert Zaniah::Accessibility.perform(window, node, :press)
    assert_equal 1, presses
  ensure
    window&.close
    app&.executor&.shutdown
  end

  def test_mac_role_map_covers_every_component_role
    roles = %i[text image separator group progressbar button checkbox radio radiogroup switch slider meter tooltip
      menu menubar textbox searchbox combobox listbox navigation toolbar status dialog list table tree form]
    assert_empty roles - Zaniah::Accessibility::Mac::ROLES.keys
  end

  def test_mac_native_element_exposes_and_performs_press
    skip "macOS only" unless RUBY_PLATFORM.include?("darwin")
    require "zaniah/platform/mac"
    app = Zaniah::App.new
    window = app.open_window(width: 120, height: 60)
    presses = 0
    window.draw { Zaniah::UI::Button.new("Save").on_click { presses += 1 } }
    window.tick
    o = Zaniah::Platform::Mac::O
    Zaniah::Platform::Mac::App.instance
    native_window = o.send(o.alloc("NSWindow"), "initWithContentRect:styleMask:backing:defer:",
      [0, 0, 120, 60], 15, 2, 0, args: [:rect, :ulong, :ulong, :bool])
    native_view = o.send(o.alloc("NSView"), "initWithFrame:", [0, 0, 120, 60], args: [:rect])
    o.send(native_window, "setContentView:", native_view, args: [:pointer], result: :void)
    window.define_singleton_method(:handle) { native_window }
    window.define_singleton_method(:view) { native_view }
    tree = window.accessibility_tree
    Zaniah::Accessibility::Mac.publish(window, tree.root, tree.changes)
    children = o.send(native_view, "accessibilityChildren")
    button = o.send(children, "objectAtIndex:", 0, args: [:ulong])
    actions = o.send(button, "accessibilityActionNames")

    assert_equal "AXButton", o.text(o.send(button, "accessibilityRole"))
    assert_equal "AXPress", o.text(o.send(actions, "objectAtIndex:", 0, args: [:ulong]))
    o.send(button, "accessibilityPerformAction:", o.string("AXPress"), args: [:pointer], result: :void)
    assert_equal 1, presses
  ensure
    Zaniah::Accessibility::Mac.close(window) if window
    o&.send(native_window, "close", result: :void) if native_window&.positive?
    [native_view, native_window].compact.each { |object| o&.release(object) }
    window&.close
    app&.executor&.shutdown
  end
end
