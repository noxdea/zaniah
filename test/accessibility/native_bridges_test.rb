# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class NativeAccessibilityBridgesTest < Minitest::Test
  FakeDispatcher = Struct.new(:focused)
  FakeWindow = Struct.new(:handle, :scale_factor, :dispatcher)

  def test_native_tree_indexes_navigation_bounds_and_hit_testing
    child = Zaniah::Accessibility.node(role: :button, id: :save, label: "Save", actions: [:press])
    root = Zaniah::Accessibility.node(role: :group, bounds: Zaniah::Bounds.new(10, 20, 100, 50), children: [child])
    tree = Zaniah::Accessibility::NativeTree.new(root)

    assert_same tree.root, tree[[].freeze]
    assert_same tree.root, tree.root.children.first.parent
    assert_equal root.bounds, tree.bounds(tree.root.children.first)
    assert_equal [0], tree.hit(Zaniah::Point.new(15, 25)).path
    assert_equal :save, tree.root.children.first.node.id
  end

  def test_windows_provider_keeps_identity_across_reordering
    first = Zaniah::Accessibility.node(role: :button, id: :first, label: "First", actions: [:press])
    second = Zaniah::Accessibility.node(role: :button, id: :second, label: "Second", actions: [:press])
    bridge = Zaniah::Accessibility::Windows::Provider::Bridge.new(FakeWindow.new(1, 1, FakeDispatcher.new))
    bridge.update(Zaniah::Accessibility.node(role: :group, children: [first, second]))
    provider = bridge.provider(bridge.tree.root.children.first)
    runtime_id = bridge.tree.root.children.first.runtime_id

    bridge.update(Zaniah::Accessibility.node(role: :group, children: [second, first]))

    entry = bridge.tree.root.children.last
    assert_equal runtime_id, entry.runtime_id
    assert_same provider, bridge.provider(entry)
  end

  def test_native_identity_survives_temporary_removal_without_reusing_ids
    kept = Zaniah::Accessibility.node(role: :button, id: :kept)
    hidden = Zaniah::Accessibility.node(role: :button, id: :hidden)
    first = Zaniah::Accessibility::NativeTree.new(
      Zaniah::Accessibility.node(role: :group, children: [kept, hidden]))
    hidden_id = first.root.children.last.runtime_id

    second = Zaniah::Accessibility::NativeTree.new(
      Zaniah::Accessibility.node(role: :group, children: [kept]), previous: first)
    added = Zaniah::Accessibility.node(role: :button, id: :added)
    third = Zaniah::Accessibility::NativeTree.new(
      Zaniah::Accessibility.node(role: :group, children: [kept, added]), previous: second)
    refute_equal hidden_id, third.root.children.last.runtime_id

    returned = Zaniah::Accessibility::NativeTree.new(
      Zaniah::Accessibility.node(role: :group, children: [kept, hidden]), previous: third)
    assert_equal hidden_id, returned.root.children.last.runtime_id

    bridge = Zaniah::Accessibility::Windows::Provider::Bridge.new(FakeWindow.new(1, 1, FakeDispatcher.new))
    bridge.update(first.root.node)
    hidden_provider = bridge.provider(bridge.tree.root.children.last)
    bridge.update(second.root.node)
    bridge.update(third.root.node)
    bridge.update(returned.root.node)
    assert_same hidden_provider, bridge.provider(bridge.tree.root.children.last)
  end

  def test_native_invoke_performs_only_one_semantic_action
    performed = []
    action_tree = Object.new
    action_tree.define_singleton_method(:perform) { |_node, action| performed << action; true }
    window = Struct.new(:handle, :scale_factor, :dispatcher, :accessibility_tree)
      .new(1, 1, FakeDispatcher.new, action_tree)
    node = Zaniah::Accessibility.node(role: :treeitem, id: :item,
      actions: %i[select expand])

    Zaniah::Accessibility::Mac::ELEMENTS[1] = [window, node, nil, 1]
    assert Zaniah::Accessibility::Mac.perform_native(1, "AXPress")
    bridge = Zaniah::Accessibility::Windows::Provider::Bridge.new(window)
    bridge.update(Zaniah::Accessibility.node(role: :group, children: [node]))
    assert_equal 0, bridge.provider(bridge.tree.root.children.first).invoke

    assert_equal %i[select select], performed
  ensure
    Zaniah::Accessibility::Mac::ELEMENTS.delete(1)
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

    slider = Zaniah::Accessibility.node(role: :slider, value: 50, actions: %i[increment decrement])
    bridge.update(Zaniah::Accessibility.node(role: :group, children: [slider]))
    provider = bridge.provider(bridge.tree.root.children.first)
    assert_equal 0, provider.pattern(10_003, pointer)
    assert_equal 0, pointer[0, Fiddle::SIZEOF_VOIDP].unpack1("J")

    separator = Zaniah::Accessibility.node(role: :separator, id: :split, value: 0.5,
      states: {minimum: 0.1, maximum: 0.9}, actions: %i[increment decrement])
    bridge.update(Zaniah::Accessibility.node(role: :group, children: [separator]))
    provider = bridge.provider(bridge.tree.root.children.first)
    assert_equal 0, provider.pattern(10_003, pointer)
    assert_equal provider.pointer(:range), pointer[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
  end

  def test_native_action_routes_back_through_the_rendered_control
    app = Zaniah::App.new
    window = app.open_window(width: 120, height: 60)
    presses = 0
    window.draw { Zaniah::UI::Button.new("Save").test_id("save").on_click { presses += 1 } }
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

  def test_native_notification_mappings_cover_semantic_events
    node = Zaniah::Accessibility.node(role: :status, id: :notice, label: "Done")
    events = %i[structure property layout focus announcement].map do |kind|
      Zaniah::Accessibility::Event.new(kind: kind, id: :notice, path: [], node: node)
    end

    assert_equal [20_002, 20_004, 20_008, 20_005, 20_024],
      Zaniah::Accessibility::Windows.event_ids(events)
    assert_equal %w[AXLayoutChanged AXValueChanged AXLayoutChanged AXFocusedUIElementChanged AXAnnouncementRequested],
      Zaniah::Accessibility::Mac.notifications(events).map(&:last)
  end

  def test_mac_native_element_exposes_and_performs_press
    skip "macOS only" unless RUBY_PLATFORM.include?("darwin")
    require "zaniah/platform/mac"
    app = Zaniah::App.new
    window = app.open_window(width: 120, height: 60)
    presses = 0
    window.draw { Zaniah::UI::Button.new("Save").test_id("save").on_click { presses += 1 } }
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
    assert_equal "save", o.text(o.send(button, "accessibilityIdentifier"))
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
