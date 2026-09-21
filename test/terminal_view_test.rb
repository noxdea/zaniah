# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"

class TerminalViewTest < Minitest::Test
  Cell = Data.define(:text, :width, :foreground, :background)

  Grid = Struct.new(:columns, :rows, :cells, :cursor_x, :cursor_y, :cursor_visible, keyword_init: true) do
    attr_accessor :damage
    def clear_damage = (@damage = nil)
  end

  def test_update_keeps_damage_outside_element_tree
    grid = Grid.new(columns: 2, rows: 1, cells: [[Cell.new("a", 1, nil, nil), Cell.new(" ", 1, nil, nil)]],
      cursor_x: 0, cursor_y: 0, cursor_visible: true)
    view = Zaniah::UI::TerminalView.new(grid: grid)
    assert_equal 0...1, view.damage
    view.update(damage: 0...1)
    assert_equal 0...1, view.damage
    view.select(0...1)
    assert_equal 0...1, view.selection
  end

  def test_rejects_invalid_grid
    assert_raises(ArgumentError) { Zaniah::UI::TerminalView.new(grid: Object.new) }
  end
end
