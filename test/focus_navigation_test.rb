# frozen_string_literal: true

require_relative "test_helper"

class FocusNavigationTest < Minitest::Test
  T = Zaniah

  def test_tab_order_spatial_navigation_and_trap
    root = T::Input::FocusHandle.new
    first = T::Input::FocusHandle.new(parent: root, tab_index: 1, bounds: T::Bounds.new(0, 0, 10, 10))
    earlier = T::Input::FocusHandle.new(parent: root, tab_index: 0, bounds: T::Bounds.new(20, 0, 10, 10))
    disabled = T::Input::FocusHandle.new(parent: root, tab_index: -1, focusable: false)
    tree = T::Input::FocusTree.new.register(root)

    assert_same earlier, tree.next
    assert_same first, tree.next(earlier)
    assert_same first, tree.previous(earlier)
    assert_same earlier, tree.spatial(first, :right)
    assert_nil tree.spatial(first, :left)

    tree.trap(first) do
      assert_same first, tree.next
      refute_same disabled, tree.next
    end
    assert_same earlier, tree.next
  end

  def test_element_focus_origin_default_ring_cursor_and_scrolling
    child = T::Div.new.h(100).focusable.cursor(:pointer).focus_visible { |style| style.ring(1) }
    view = T::ScrollView.new(axis: :vertical).w(20).h(20).child(child)
    window = T::Platform.open_window(width: 20, height: 20)
    window.render(view)

    window.input(T::Input::KeyDown.new("tab", false))
    assert_same child.focus_handle, window.dispatcher.focused
    assert window.dispatcher.focus_visible?
    assert_equal 80, view.scroll_state.offset.y

    window.render(view)
    assert child.resolved_style[:ring]
    window.input(T::Input::MouseMove.new(T::Point.new(5, 5), []))
    window.render(view)
    assert_equal :pointer, window.cursor_style
    window.input(T::Input::MouseDown.new(T::Point.new(5, 5), :left, [], 1))
    refute window.dispatcher.focus_visible?
  ensure
    window&.close
  end

  def test_platform_keymap_uses_the_native_primary_modifier
    mac = T::Input::Keymap.platform_defaults(:mac)
    windows = T::Input::Keymap.platform_defaults(:windows)
    context = {in_text_field: true}
    assert_equal :select_all, mac.dispatch("cmd-a", context: context)
    assert_nil mac.dispatch("ctrl-a", context: context)
    assert_equal :select_all, windows.dispatch("ctrl-a", context: context)
  end
end
