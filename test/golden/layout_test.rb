# frozen_string_literal: true

require_relative "../test_helper"

class GoldenLayoutTest < Zaniah::UITest
  T = Zaniah

  {vertical: T::Point.new(0, 80), horizontal: T::Point.new(100, 0), both: T::Point.new(100, 80)}.each do |axis, offset|
    define_method("test_scroll_#{axis}") do
      assert_golden("layout/scroll-#{axis}") do
        content = T::Div.new.w(320).h(220).bg("#334155")
          .child(T::Div.new.w(64).h(64).bg("#38bdf8").style(position: :absolute, left: 120, top: 100))
          .child(T::Div.new.w(48).h(48).bg("#f97316").style(position: :absolute, left: 260, top: 170))
        view = T::ScrollView.new(axis: axis).w(180).h(100).child(content).tap do |scroll_view|
          scroll_view.scroll_state.update(content_size: T::Size.new(320, 220), viewport_size: T::Size.new(180, 100))
          scroll_view.scroll_to(offset)
        end
        T::Div.new.child(view)
      end
    end
  end

  def test_equal_grid
    assert_golden("layout/grid-equal") { grid(T.repeat(3, T.fr(1))) }
  end

  def test_fixed_and_flexible_grid
    assert_golden("layout/grid-fixed-flex") { grid([T.px(60), T.fr(1), T.fr(2)]) }
  end

  def test_spanning_grid
    assert_golden("layout/grid-span") do
      grid(T.repeat(3, T.fr(1)), placements: [{grid_column: 1..2}, {}])
    end
  end

  def test_grid_gap
    assert_golden("layout/grid-gap") { grid(T.repeat(3, T.fr(1)), column_gap: 12) }
  end

  def test_grid_minmax
    assert_golden("layout/grid-minmax") { grid([T.minmax(T.px(120), T.fr(1)), T.fr(1)]) }
  end

  private

  def grid(columns, column_gap: 0, placements: [{}, {}, {}])
    colors = %w[#0ea5e9 #8b5cf6 #f97316]
    value = T::Div.new.w(300).h(80).style(display: :grid, grid_template_columns: columns, column_gap: column_gap)
      .children(placements.each_with_index.map { |placement, index| T::Div.new.h(80).bg(colors[index]).style(**placement) })
    T::Div.new.child(value)
  end
end
