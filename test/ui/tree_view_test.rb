# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class TreeViewTest < Minitest::Test
  T = Zaniah

  def setup
    @clock = T::TestClock.new
    @app = T::App.new(clock: @clock)
    @window = @app.open_window(width: 640, height: 360)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def render(component)
    @window.draw { component }
    @window.request_frame
    @window.tick
    component
  end

  def test_lazy_loader_retries_after_an_error_and_caches_a_success
    calls = 0
    loader = lambda do |_value|
      calls += 1
      raise "temporarily unavailable" if calls == 1

      [{id: :child, label: "Child"}]
    end
    tree = render(T::UI::TreeView.new([{id: :root, label: "Root", children: loader}]))

    assert_raises(RuntimeError) { tree.expand(:root) }
    assert_equal 1, calls
    refute_includes tree.expanded, :root

    tree.expand(:root)
    assert_equal 2, calls
    assert_includes tree.expanded, :root
    assert @window.dirty?
    render(tree)

    tree.collapse(:root).expand(:root)
    assert_equal 2, calls
    assert_equal %w[Root Child], tree.accessibility_node(nil).children.map(&:label)
  end

  def test_toggle_requests_a_frame_even_if_the_callback_raises
    tree = render(T::UI::TreeView.new([{id: :root, label: "Root", children: ["Child"]}]))
    tree.on_toggle { raise "callback failed" }

    assert_raises(RuntimeError) { tree.expand(:root) }

    assert_includes tree.expanded, :root
    assert @window.dirty?
  end

  def test_large_tree_only_materializes_viewport_rows_for_layout_and_accessibility
    reads = {labels: 0, loaders: 0}
    item_class = Struct.new(:id, :reads) do
      def label
        reads[:labels] += 1
        "Node #{id}"
      end

      def children
        ->(_value) { reads[:loaders] += 1; [] }
      end
    end
    children = Array.new(100_000) { |index| item_class.new(index, reads) }
    tree = T::UI::TreeView.new([
      {id: :root, label: "Root", children: ->(_value) { reads[:loaders] += 1; children }}
    ], height: 84)

    render(tree)
    assert_equal 0, reads[:loaders]
    tree.expand(:root)
    render(tree)
    node = tree.accessibility_node(nil)

    assert_operator tree.children.length, :<, 20
    assert_operator node.children.length, :<, 20
    assert_operator tree.instance_variable_get(:@locations).length, :<, 20
    assert_operator reads[:labels], :<, 100
    assert_equal 1, reads[:loaders]
    assert_equal 100_001, node.states[:size]
  end

  def test_replace_preserves_expansion_and_selection_by_stable_id
    tree = render(T::UI::TreeView.new([
      {id: :root, label: "Root", children: [{id: :branch, label: "Branch", children: [{id: :leaf, label: "Old"}]}]}
    ], selected: :leaf))
    tree.expand(:root).expand(:branch)
    render(tree)

    tree.replace([
      {id: :other, label: "Other"},
      {id: :root, label: "Renamed", children: [{id: :branch, label: "Branch", children: [{id: :leaf, label: "New"}]}]}
    ])
    render(tree)

    assert_equal Set[:root, :branch], tree.expanded
    assert_equal :leaf, tree.selected_id
    assert_equal %w[Other Renamed Branch New], tree.accessibility_node(nil).children.map(&:label)
  end

  def test_replace_preserves_loaded_children_without_firing_the_loader
    loads = 0
    loader = ->(_value) { loads += 1; [{id: :child, label: "Child"}] }
    tree = render(T::UI::TreeView.new([{id: :root, label: "Root", children: loader}]))
    tree.expand(:root)
    render(tree)

    tree.replace([{id: :root, label: "Renamed", children: loader}])
    render(tree)

    assert_equal 1, loads
    assert_includes tree.expanded, :root
    assert_equal %w[Renamed Child], tree.accessibility_node(nil).children.map(&:label)
  end

  def test_duplicate_ids_are_rejected_when_their_rows_are_materialized
    tree = T::UI::TreeView.new([{id: :same, label: "One"}, {id: :same, label: "Two"}])

    error = assert_raises(ArgumentError) { render(tree) }

    assert_includes error.message, "duplicate tree item id :same"
  end

  def test_arrow_keys_enter_children_return_to_parents_and_scroll_selection
    rows = Array.new(100) { |index| {id: index, label: "Row #{index}"} }
    tree = render(T::UI::TreeView.new([{id: :root, label: "Root", children: rows}], height: 84, selected: :root))
    @window.dispatcher.focus(tree.focus_handle)

    @window.input(T::Input::KeyDown.new("right", false))
    render(tree)
    @window.input(T::Input::KeyDown.new("right", false))
    assert_equal 0, tree.selected_id
    @window.input(T::Input::KeyDown.new("left", false))
    assert_equal :root, tree.selected_id

    @window.input(T::Input::KeyDown.new("end", false))
    render(tree)
    assert_equal 99, tree.selected_id
    assert_operator tree.instance_variable_get(:@list).scroll_y, :>, 0
    assert_includes tree.instance_variable_get(:@list).visible_range, 100

    empty = render(T::UI::TreeView.new([]))
    @window.dispatcher.focus(empty.focus_handle)
    @window.input(T::Input::KeyDown.new("left", false))
  end

  def test_accessibility_uses_the_new_count_before_relayout
    rows = Array.new(100) { |index| {id: index, label: "Row #{index}"} }
    tree = render(T::UI::TreeView.new([{id: :root, label: "Root", children: rows}],
      height: 84, selected: :root))
    tree.expand(:root)
    render(tree)
    @window.dispatcher.focus(tree.focus_handle)
    @window.input(T::Input::KeyDown.new("end", false))
    render(tree)

    tree.collapse(:root)

    assert_equal ["Root"], tree.accessibility_node(nil).children.map(&:label)
  end

  def test_accessibility_items_keep_ids_bounds_focus_and_direct_actions
    tree = render(T::UI::TreeView.new([
      {id: :root, label: "Root", children: [{id: :child, label: "Child"}]}
    ], selected: :root))
    @window.dispatcher.focus(tree.focus_handle)
    render(tree)
    root = @window.accessibility_tree.root.children.first

    assert_equal :root, root.id
    assert_instance_of T::Bounds, root.bounds
    assert_equal true, root.states[:focused]
    assert_equal %i[select expand], root.actions
    assert T::Accessibility.perform(@window, root, :expand)
    render(tree)

    child = @window.accessibility_tree.root.children.last
    assert_equal :child, child.id
    assert T::Accessibility.perform(@window, child, :select)
    assert_equal :child, tree.selected_id
  end

  def test_accessibility_actions_support_false_ids_and_report_collapse_success
    tree = render(T::UI::TreeView.new([
      {id: false, label: "Root", children: [{id: :child, label: "Child"}]}
    ]))
    node = @window.accessibility_tree.root.children.first

    assert_equal false, node.id
    assert T::Accessibility.perform(@window, node, :expand)
    render(tree)
    node = @window.accessibility_tree.root.children.first
    assert T::Accessibility.perform(@window, node, :collapse)
  end

  def test_virtual_scroll_moves_overlapping_accessibility_items_by_id
    tree = render(T::UI::TreeView.new(Array.new(100) { |index| {id: index, label: "Row #{index}"} }, height: 84))
    before = T::Accessibility::NativeTree.new(@window.accessibility_tree.root)
    before_ids = before.to_h { |entry| [entry.node.id, entry.runtime_id] }

    tree.instance_variable_get(:@list).scroll_to(3)
    render(tree)
    after = T::Accessibility::NativeTree.new(@window.accessibility_tree.root, previous: before)
    overlapping = before_ids.keys.compact & after.map { |entry| entry.node.id }.compact

    refute_empty overlapping
    assert @window.accessibility_tree.changes.any? { |change| change.kind == :moved }
    overlapping.each do |id|
      assert_equal before_ids[id], after.find { |entry| entry.node.id == id }.runtime_id
    end
  end
end
