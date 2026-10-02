# frozen_string_literal: true

require "test_helper"

class MutableListsTest < Minitest::Test
  def context
    Struct.new(:window).new(Struct.new(:content_size).new(Zaniah::Size.new(200, 100)))
  end

  def test_uniform_list_growth_preserves_scroll_and_follows_only_from_bottom
    list = Zaniah::UniformList.new(count: 10, row_height: 20, stick_to_bottom: true) { Zaniah::Div.new }
    list.request_layout(context)
    state = list.scroll_state
    list.scroll_y = 40
    list.count = 20
    assert_equal 40, list.scroll_y
    assert_same state, list.scroll_state
    list.scroll_y = 300
    assert list.at_bottom?
    list.count = 25
    assert_equal 400, list.scroll_y
    list.count = 2
    assert_equal 0, list.scroll_y
    assert_raises(ArgumentError) { list.count = 1.5 }
  end

  def test_variable_list_growth_retains_measurements_and_clamps_shrink
    list = Zaniah::List.new(count: 10, estimated_height: 20, stick_to_bottom: true) { Zaniah::Div.new.h(20) }
    list.request_layout(context)
    list.update_height(0, 40)
    list.scroll_y = 120
    list.count = 15
    assert_equal 40, list.heights[0]
    assert_equal 320, list.total_height
    assert_equal 220, list.scroll_y
    list.count = 2
    assert_equal 60, list.total_height
    assert_equal 0, list.scroll_y
    list.count = 10
    assert_equal 40, list.heights[0]
    assert_equal 220, list.total_height
  end

  def test_resized_fenwick_tree_matches_array_oracle
    heights = Zaniah::List::HeightIndex.new(3, 10)
    heights.update(1, 30)
    heights.count = 20
    assert_equal 220, heights.total
    assert_equal 60, heights.prefix(4)
    heights.count = 1
    heights.count = 5
    assert_equal 50, heights.total
  end
end
