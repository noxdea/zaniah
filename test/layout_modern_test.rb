# frozen_string_literal: true

require_relative "test_helper"

class LayoutModernTest < Minitest::Test
  T = Zaniah

  def test_scroll_state_clamps_preserves_anchor_and_reveals_rect
    state = T::ScrollState.new(axis: :vertical)
    state.update(content_size: T::Size.new(100, 500), viewport_size: T::Size.new(100, 100))
    state.scroll_to(450)
    assert_equal 400, state.offset.y
    assert state.at_bottom?

    state.preserve_anchor(-25)
    assert_equal 375, state.offset.y
    state.scroll_rect(T::Bounds.new(0, 100, 10, 20))
    assert_equal 100, state.offset.y
  end

  def test_grid_tracks_spans_gaps_and_minmax
    equal = grid([T.fr(1), T.fr(1)], 200, 100, 2)
    assert_equal [100, 100], equal.children.map { |child| child.bounds.width }

    mixed = grid([T.px(40), T.fr(1)], 200, 100, 2)
    assert_equal [40, 160], mixed.children.map { |child| child.bounds.width }

    span = T::Layout::Node.new(style: {display: :grid, grid_template_columns: T.repeat(3, T.fr(1))},
      children: [T::Layout::Node.new(style: {grid_column: 1..2})])
    T::Layout::Engine.new.compute(span, width: 300, height: 100)
    assert_equal 200, span.children.first.bounds.width

    gap = grid([T.fr(1), T.fr(1)], 200, 100, 2, column_gap: 10)
    assert_equal [95, 95], gap.children.map { |child| child.bounds.width }
    assert_equal 105, gap.children.last.bounds.x

    constrained = grid([T.minmax(T.px(120), T.fr(1)), T.fr(1)], 200, 100, 2)
    assert_equal [120, 80], constrained.children.map { |child| child.bounds.width }
  end

  def test_grid_places_explicit_items_before_auto_items
    auto = T::Layout::Node.new
    explicit = T::Layout::Node.new(style: {grid_column: 1, grid_row: 1})
    root = T::Layout::Node.new(style: {display: :grid, grid_template_columns: T.repeat(2, T.fr(1))},
      children: [auto, explicit])
    T::Layout::Engine.new.compute(root, width: 200, height: 100)
    assert_equal T::Bounds.new(0, 0, 100, 0), explicit.bounds
    assert_equal 100, auto.bounds.x
  end

  def test_aspect_ratio_and_logical_edges
    child = T::Layout::Node.new(style: {width: 80, aspect_ratio: 2})
    root = T::Layout::Node.new(style: {padding_start: 10, padding_end: 20, direction: :rtl}, children: [child])
    T::Layout::Engine.new.compute(root, width: 200, height: 100)
    assert_equal T::Bounds.new(20, 0, 80, 40), child.bounds
  end

  def test_scroll_view_offsets_clips_hits_and_sticks
    window = T::Platform.open_window(width: 100, height: 50)
    clicked = false
    sticky = T::Div.new.w(100).h(10).style(position: :sticky, top: 0).on_click { clicked = true }
    content = T::Div.new.w(100).h(120).on_hover {}.child(sticky)
    view = T::ScrollView.new.w(100).h(50).child(content)
    view.scroll_state.update(content_size: T::Size.new(100, 120), viewport_size: T::Size.new(100, 50))
    view.scroll_to(30)
    window.render(view)

    assert_equal(-30, content.layout_node.bounds.y)
    assert_equal 0, sticky.layout_node.bounds.y
    window.input(T::Input::MouseDown.new(T::Point.new(5, 5), :left, [], 1))
    assert clicked
    assert_equal 50, window.dispatcher.hits.find { |hit| hit.owner.equal?(content) }.bounds.height
  ensure
    window&.close
  end

  def test_scrollbar_drag_updates_offset
    state = T::ScrollState.new(axis: :vertical)
    state.update(content_size: T::Size.new(10, 1_000), viewport_size: T::Size.new(10, 100))
    bar = T::UI::Scrollbar.new(state).h(100)
    window = T::Platform.open_window(width: 10, height: 100)
    window.render(bar)
    window.input(T::Input::MouseDown.new(T::Point.new(4, 5), :left, [], 1))
    window.input(T::Input::MouseMove.new(T::Point.new(4, 45), []))
    assert_in_delta 450, state.offset.y
    window.dispatcher.focus(bar.focus_handle)
    window.input(T::Input::KeyDown.new("end", false))
    assert_equal state.max_offset.y, state.offset.y
    assert_equal :scrollbar, bar.accessibility_node(nil).role
  ensure
    window&.close
  end

  private

  def grid(columns, width, height, count, **style)
    T::Layout::Node.new(style: {display: :grid, grid_template_columns: columns, **style},
      children: Array.new(count) { T::Layout::Node.new }).tap do |root|
      T::Layout::Engine.new.compute(root, width: width, height: height)
    end
  end
end
