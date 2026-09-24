# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class GridClipboardTest < Minitest::Test
  T = Zaniah

  def setup
    @app = T::App.new
    @window = @app.open_window(width: 360, height: 220)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def render(component)
    @window.draw { component }
    @window.request_frame
    @window.tick
    @window.dispatcher.focus(component.focus_handle)
    component
  end

  def test_grid_copy_and_paste_pass_half_open_areas_and_all_mime_types
    area = T::UI::Grid::Area.new(rows: 0...2, columns: 1...3)
    copy_count = 0
    copied = nil
    pasted = nil
    grid = T::UI::Grid.new(rows: 3, columns: 3) { "cell" }.w(300).h(100)
      .on_copy do |areas, cx|
        copy_count += 1
        copied = [areas, cx]
        {"text/plain" => "A\tB\nC\tD", "text/html" => "<table><tr><td>A</td></tr></table>"}
      end
      .on_paste { |areas, content, cx| pasted = [areas, content, cx] }
    grid.selection = [area]
    render(grid)

    assert_equal :enabled, @window.dispatcher.available?(:copy)
    assert @window.dispatcher.perform(:copy, source: :menu)
    assert_equal [area], copied.first
    assert_same @window, copied.last.window
    assert_equal ["text/plain", "text/html"], @window.clipboard_types
    assert_equal "A\tB\nC\tD", @window.clipboard
    primary = RUBY_PLATFORM.include?("darwin") ? "cmd" : "ctrl"
    @window.input(T::Input::KeyDown.new("#{primary}-c", false))
    assert_equal 2, copy_count

    assert @window.dispatcher.perform(:paste, source: :menu)
    assert_equal [area], pasted.first
    assert_equal "A\tB\nC\tD", pasted[1].fetch("text/plain")
    assert_equal "<table><tr><td>A</td></tr></table>", pasted[1].fetch("text/html")
    assert_same @window, pasted.last.window
  end

  def test_table_copy_and_paste_use_display_order_without_changing_identity_selection
    rows = (1..4).map { |id| {id: id, name: "Row #{id}"} }
    copied = nil
    pasted = nil
    table = T::UI::Table.new(rows, columns: %i[id name], height: 180,
      selection: :multiple, row_key: ->(row) { row[:id] })
      .on_copy do |areas, _cx|
        copied = areas
        {"text/plain" => "4\tRow 4\n2\tRow 2", "text/html" => "<table>two rows</table>"}
      end
      .on_paste { |areas, content, _cx| pasted = [areas, content] }
    table.sort_by(:id, direction: :desc)
    render(table)
    @window.input(T::Input::MouseDown.new(T::Point.new(20, 45), :left, [], 1))
    @window.input(T::Input::MouseDown.new(T::Point.new(20, 109), :left, [:ctrl], 1))
    @window.dispatcher.focus(table.focus_handle)
    assert_equal Set[4, 2], table.selection

    assert @window.dispatcher.perform(:copy)
    assert_equal [
      T::UI::Grid::Area.new(rows: 0...1, columns: 0...2),
      T::UI::Grid::Area.new(rows: 2...3, columns: 0...2)
    ], copied
    assert_equal "4\tRow 4\n2\tRow 2", @window.clipboard
    assert @window.dispatcher.perform(:paste)
    assert_equal copied, pasted.first
    assert_equal "<table>two rows</table>", pasted.last.fetch("text/html")
    assert_equal Set[4, 2], table.selection
  end

  def test_missing_hooks_are_unhandled_and_hooks_without_selection_are_disabled
    grid = render(T::UI::Grid.new(rows: 1, columns: 1) { "cell" })
    assert_equal :unhandled, @window.dispatcher.available?(:copy)
    assert_equal :unhandled, @window.dispatcher.available?(:paste)
    refute @window.dispatcher.perform(:copy)
    refute @window.dispatcher.perform(:paste)
    fallback = 0
    @app.actions.register(:copy, title: "Copy") { |_cx| fallback += 1 }
    assert_equal :enabled, @window.dispatcher.available?(:copy)
    assert @window.dispatcher.perform(:copy)
    assert_equal 1, fallback

    grid.on_copy { {"text/plain" => "cell"} }.on_paste { flunk "empty selection" }
    assert_equal :disabled, @window.dispatcher.available?(:copy)
    assert_equal :disabled, @window.dispatcher.available?(:paste)
    grid.selection = [T::UI::Grid::Area.new(rows: 0...1, columns: 0...1)]
    assert_equal :enabled, @window.dispatcher.available?(:copy)

    table = render(T::UI::Table.new([{id: 1}], columns: [:id]).on_copy { {"text/plain" => "1"} })
    assert_equal :disabled, @window.dispatcher.available?(:copy)
    assert_equal :unhandled, @window.dispatcher.available?(:paste)
    refute @window.dispatcher.perform(:copy)
  end
end
