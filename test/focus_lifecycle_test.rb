# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"

class FocusLifecycleTest < Minitest::Test
  T = Zaniah

  def test_rebuilt_tree_rows_release_old_focus_links_and_tab_targets
    tree = T::UI::TreeView.new([{id: :root, label: "Root", children: [
      {id: :first, label: "First"}, {id: :second, label: "Second"}
    ]}], height: 84)
    tree.expand(:root)
    window = T::Platform.open_window(backend: :headless, width: 320, height: 120)
    previous = []
    6.times do
      window.render(tree, present: false)
      current = tree.root.children.flat_map(&:children).filter_map { |item| item.focus_handle if item.respond_to?(:focus_handle) }
      assert_equal 3, current.size
      assert_equal current.map(&:object_id), tree.focus_handle.children.map(&:object_id)
      assert previous.all? { |handle| handle.parent.nil? }, "obsolete rows must release their automatic parent"
      assert window.dispatcher.focus_tree.next(tree.focus_handle).equal?(current.first), "Tab must reach a current row"
      previous = current
    end
    window.dispatcher.focus(tree.focus_handle, origin: :keyboard)
    tree.select_id(:first)
    window.render(tree, present: false)
    window.dispatcher.key("down")
    assert_equal :second, tree.selected_id
    window.render(tree, present: false)
    semantic = window.accessibility_tree.find { |node| node.id == :second }
    assert semantic.states[:selected]
    assert semantic.states[:focused]
  ensure
    window&.close
  end

  def test_reused_focus_hierarchy_keeps_handlers_context_and_traps_across_frames
    keymap = T::Input::Keymap.new.bind("ctrl-s", :save, context: "within_scope")
    window = T::Platform.open_window(backend: :headless, width: 40, height: 40, keymap: keymap)
    actions, inputs, focus_events = [], [], []
    scope = T::Div.new.focusable(context: {within_scope: true}) { |action| actions << action; true }
    child = T::Div.new.w(20).h(20).focusable { false }
    scope.child(child)
    child.focus_handle.on_focus = ->(focused) { focus_events << focused }
    child.focus_handle.on_input = ->(_event) { inputs << :child; false }
    scope.focus_handle.on_input = ->(_event) { inputs << :scope; true }
    window.render(scope, present: false)
    dispatcher = window.dispatcher
    dispatcher.focus(child.focus_handle, origin: :keyboard)
    dispatcher.focus_tree.trap(scope.focus_handle)
    2.times do
      window.render(scope, present: false)
      assert child.focus_handle.parent.equal?(scope.focus_handle), "the reused child must remain in its scope"
      assert_equal [child.focus_handle.object_id], scope.focus_handle.children.map(&:object_id)
      assert dispatcher.focused.equal?(child.focus_handle), "the reused child must retain focus"
      assert dispatcher.focus_visible?
      assert dispatcher.focus_tree.allows?(child.focus_handle)
      assert_equal :save, dispatcher.key("ctrl-s")
      assert dispatcher.input(T::Input::KeyDown.new("x", false))
    end
    assert_equal [:save, :save], actions
    assert_equal %i[child scope child scope], inputs
    assert_equal [true], focus_events
    dispatcher.focus_tree.release_trap(scope.focus_handle)
  ensure
    window&.close
  end

  def test_clear_preserves_manual_hierarchy_and_explicit_reparenting
    dispatcher = T::Input::Dispatcher.new
    manual = T::Input::FocusHandle.new(focusable: false)
    child = T::Input::FocusHandle.new(parent: manual, tab_index: 0)
    dispatcher.register_focus(child)
    dispatcher.clear_hits
    assert child.parent.equal?(manual), "clearing rendered hits must preserve manual hierarchy"
    assert_equal [child.object_id], manual.children.map(&:object_id)
    assert_nil dispatcher.focus_tree.next
    dispatcher.register_focus(child)
    assert dispatcher.focus_tree.next.equal?(child), "manual hierarchy must remain navigable after registration"

    scope = T::Div.new.focusable
    element = T::Div.new.focusable
    element.send(:parent=, scope)
    dispatcher.register_focus(element.focus_handle)
    element.focus_handle.parent = manual
    dispatcher.clear_hits
    assert element.focus_handle.parent.equal?(manual), "clearing must preserve an explicit replacement parent"
    assert_empty scope.focus_handle.children
    assert_equal [child.object_id, element.focus_handle.object_id], manual.children.map(&:object_id)
  end

  def test_parent_detach_and_self_parent_rejection_preserve_bidirectional_links
    first, second, child = 3.times.map { T::Input::FocusHandle.new }
    child.parent = first
    child.parent = first
    assert_equal [child.object_id], first.children.map(&:object_id)
    assert_raises(ArgumentError) { child.parent = child }
    assert child.parent.equal?(first), "rejecting a self-parent must leave the original relationship intact"
    child.parent = second
    assert_empty first.children
    assert_equal [child.object_id], second.children.map(&:object_id)
    child.parent = nil
    assert_nil child.parent
    assert_empty second.children
  end
end
