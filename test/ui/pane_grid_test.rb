# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class PaneGridTest < Minitest::Test
  T = Zaniah

  def setup
    @app = T::App.new
    @window = @app.open_window(width: 200, height: 100, scale_factor: 2)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_fixed_fractional_and_minmax_tracks_layout_arbitrary_matrix
    grid = render(grid_with(columns: [T.px(40), T.fr(1)],
      rows: [T.minmax(T.px(20), T.fr(1)), T.fr(1)]))

    assert_equal [40, 154], grid.track_sizes(:columns)
    assert_equal [47, 47], grid.track_sizes(:rows)
    assert_equal %i[a b c d], grid.pane_ids
    assert_equal "A │ B\n───\nC │ D", grid.tui_cells
    assert_equal 4, grid.accessibility_node(nil).children.count { |node| node.states.key?(:pane_id) }
    assert_equal 2, grid.accessibility_node(nil).children.count { |node| node.role == :separator }
    assert grid.accessibility_node(nil).children.all?(&:bounds)
  end

  def test_pointer_and_keyboard_resize_clamp_in_logical_hidpi_coordinates
    events = []
    grid = render(grid_with.on_resize { |event, _context| events << event })
    divider = grid.divider_handle(:columns, 0).bounds
    intersection_y = grid.divider_handle(:rows, 0).bounds.y + 1

    point = T::Point.new(divider.x + divider.width / 2, intersection_y)
    @window.input(T::Input::MouseDown.new(point, :left, [], 1))
    @window.input(T::Input::MouseMove.new(T::Point.new(point.x + 30, point.y), []))
    @window.input(T::Input::MouseUp.new(T::Point.new(point.x + 30, point.y), :left, []))
    @window.tick

    assert_in_delta 127, grid.track_sizes(:columns).first, 0.001
    assert_equal [47, 47], grid.track_sizes(:rows)
    assert_equal :columns, events.last.axis

    @window.dispatcher.focus(grid.divider_handle(:rows, 0))
    @window.input(T::Input::KeyDown.new("up", false))
    @window.tick
    assert_in_delta 55, grid.track_sizes(:rows).first, 0.001

    grid.resize(:columns, 0, -10_000)
    @window.tick
    assert_in_delta 24, grid.track_sizes(:columns).first, 0.001
  end

  def test_small_viewport_and_callback_failure_leave_valid_state
    grid = render(grid_with(columns: [T.px(40), T.fr(1)]))
    grid.on_resize { raise "stop" }
    assert_raises(RuntimeError) { grid.resize(:columns, 0, 10) }
    @window.resize(300, 100)
    @window.tick
    assert_equal 40, grid.track_sizes(:columns).first
    assert_raises(ArgumentError) { grid.resize(:columns, 0, Float::NAN) }

    @window.resize(4, 3)
    @window.tick
    assert grid.track_sizes(:columns).all? { |size| size.finite? && size >= 0 }
    assert grid.track_sizes(:rows).all? { |size| size.finite? && size >= 0 }
  end

  def test_resizes_accumulate_before_layout_and_keep_minmax_minimum
    grid = render(grid_with(columns: [T.minmax(T.px(80), T.fr(1)), T.fr(1)]))
    initial = grid.track_sizes(:columns).first
    2.times { grid.resize(:columns, 0, 5) }
    assert_in_delta initial + 10, grid.track_sizes(:columns).first, 0.001
    @window.tick
    assert_in_delta initial + 10, grid.track_sizes(:columns).first, 0.001

    grid.resize(:columns, 0, -10_000)
    @window.tick
    assert_in_delta 80, grid.track_sizes(:columns).first, 0.001
  end

  def test_resize_respects_both_tracks_minmax_bounds
    @window.resize(120, 100)
    grid = render(grid_with(columns: [T.minmax(T.px(40), T.px(80)), T.minmax(T.px(30), T.px(70))]))
    @window.dispatcher.focus(grid.divider_handle(:columns, 0))

    @window.input(T::Input::KeyDown.new("home", false))
    @window.tick
    assert_in_delta 44, grid.track_sizes(:columns).first, 0.001
    assert_in_delta 70, grid.track_sizes(:columns).last, 0.001

    @window.input(T::Input::KeyDown.new("end", false))
    @window.tick
    assert_in_delta 80, grid.track_sizes(:columns).first, 0.001
    assert_in_delta 34, grid.track_sizes(:columns).last, 0.001
  end

  def test_resize_callback_cannot_replace_the_grid
    grid = render(grid_with)
    original_ids = grid.pane_ids
    grid.on_resize { grid.replace([[[:replacement, label("Replacement")], nil], [nil, nil]]) }

    assert_raises(T::Error) { grid.resize(:columns, 0, 5) }
    assert_equal original_ids, grid.pane_ids
  end

  def test_replace_preserves_stable_ids_and_supports_deletion_and_nested_grids
    inner = grid_with(columns: [T.fr(1), T.fr(1)], rows: [T.fr(1), T.fr(1)])
    grid = T::UI::PaneGrid.new([[[:outer, inner], [:side, label("Side")]]],
      columns: [T.fr(1), T.fr(1)], rows: [T.fr(1)])
    render(grid)
    assert_equal %i[outer side], grid.pane_ids
    assert_operator inner.track_sizes(:columns).first, :>, 0

    grid.replace([[[:side, label("Moved")], nil]])
    @window.tick
    assert_equal [:side], grid.pane_ids
    assert_equal [:pane, :side], grid.root.children.first.children.first.identity_key
    assert_raises(ArgumentError) { grid.replace([[[:same, label("A")], [:same, label("B")]]]) }
  end

  def test_rejects_invalid_dimensions_tracks_and_panes
    invalid = [0, -1, Float::NAN, Float::INFINITY]
    invalid.each do |track|
      assert_raises(ArgumentError) do
        T::UI::PaneGrid.new([[[:a, label("A")]]], columns: [track], rows: [T.fr(1)])
      end
    end
    assert_raises(ArgumentError) do
      T::UI::PaneGrid.new([[[:a, label("A")]]], columns: [T.percent(50)], rows: [T.fr(1)])
    end
    assert_raises(ArgumentError) do
      T::UI::PaneGrid.new([[[:a, label("A")]]], columns: [T.minmax(T.px(2), T.px(1))], rows: [T.fr(1)])
    end
    assert_raises(ArgumentError) do
      T::UI::PaneGrid.new([[[:a, label("A")]]], columns: [T.fr(1), T.fr(1)], rows: [T.fr(1)])
    end
    assert_raises(TypeError) do
      T::UI::PaneGrid.new([[[:a, Object.new]]], columns: [T.fr(1)], rows: [T.fr(1)])
    end
  end

  def test_accessibility_dividers_keep_identity_focus_and_resize_directly
    grid = render(grid_with)
    divider = @window.accessibility_tree.root.children.find { |node| node.role == :separator && node.states[:axis] == :columns }
    before = grid.track_sizes(:columns).first

    assert_equal [:divider, :columns, 0], divider.id
    assert_equal :vertical, divider.states[:orientation]
    assert_operator divider.states[:minimum], :>, 0
    assert_operator divider.states[:maximum], :<, 1
    refute T::Accessibility.assign(@window, divider, 0)
    assert T::Accessibility.perform(@window, divider, :increment)
    assert_same grid.divider_handle(:columns, 0), @window.dispatcher.focused
    assert_operator grid.track_sizes(:columns).first, :>, before
    assert T::Accessibility.assign(@window, @window.accessibility_tree.root.children.find { |node| node.id == divider.id }, 0.25)
    assert_in_delta grid.track_sizes(:columns).sum * 0.25, grid.track_sizes(:columns).first, 0.001
  end

  private

  def label(text) = T::UI::Label.new(text)

  def grid_with(columns: [T.fr(1), T.fr(1)], rows: [T.fr(1), T.fr(1)])
    T::UI::PaneGrid.new([
      [[:a, label("A")], [:b, label("B")]],
      [[:c, label("C")], [:d, label("D")]]
    ], columns: columns, rows: rows)
  end

  def render(component)
    @window.draw { component }
    @window.tick
    component
  end
end
