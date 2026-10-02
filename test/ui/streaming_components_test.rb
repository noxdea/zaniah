# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class StreamingComponentsTest < Minitest::Test
  T = Zaniah
  Source = Struct.new(:count, :calls, :reversed) do
    def cell(index, key)
      calls << [index, key]
      "#{key}:#{row_id(index)}"
    end
    def row_id(index) = reversed ? count - index - 1 : index
    def row_style(index) = index.odd? ? {background: "#123456", foreground: "#ffffff", strikethrough: true} : nil
  end

  def setup
    @app = T::App.new(clock: T::TestClock.new)
    @window = @app.open_window(width: 640, height: 480)
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

  def test_virtual_table_fetches_visible_cells_preserves_ids_and_scrolls_on_growth
    source = Source.new(1_000_000, [], false)
    sorted = nil
    table = render(T::UI::VirtualTable.new(source, columns: [{key: :id, width: 80}, {key: :name}], height: 160, row_height: 20, follow_tail: true)
      .on_sort { |key, direction, _| sorted = [key, direction]; source.reversed = true })
    assert_operator source.calls.size, :<, 200
    table.select(2)
    table.sort_by(:id)
    render(table)
    assert_equal [:id, :asc], sorted
    assert_equal Set[2], table.selection
    assert_equal 1_000_000, table.accessibility_node(nil).states[:row_count]
    table.scroll_to(source.count - 1, align: :end)
    source.count += 10
    render(table)
    assert table.following_tail?
    assert_includes table.body.visible_range, source.count - 1
    table.scroll_to(0)
    source.count += 10
    render(table)
    refute table.following_tail?
    assert_includes table.body.visible_range, 0
    table.column_visible(:name, false)
    assert_equal [:id], table.columns.select { |c| c[:visible] }.map { |c| c[:key] }
    assert_includes table.tui_cells, "id"
  end

  def test_hex_view_selection_highlights_keyboard_copy_and_virtualization
    bytes = (0..255).to_a.pack("C*") * 200
    selected = nil
    hex = render(T::UI::HexView.new(bytes, height: 100).on_select { |range, _| selected = range })
    assert_operator hex.body.children.size, :<, 10
    hex.highlights = [{range: 14...34, tone: :secondary}, {range: 22...23, tone: :primary}]
    hex.select(22...24)
    assert_equal 22...24, selected
    @window.dispatcher.focus(hex.focus_handle)
    @window.input(T::Input::KeyDown.new("right", false))
    assert_equal 24...25, hex.selection
    hex.scroll_to_offset(bytes.bytesize - 1)
    render(hex)
    assert_includes hex.body.visible_range, bytes.bytesize / 16 - 1
    assert_includes hex.tui_cells, "c7f0"
    assert_equal :group, hex.accessibility_node(nil).role
  end

  def test_tree_select_id_reveals_known_descendants_and_scrolls_without_replacing_list
    selected = nil
    tree = render(T::UI::TreeView.new([{id: :root, label: "Root", children: Array.new(20) { |i| {id: i, label: "Child #{i}"} }}], height: 100)
      .on_select { |value, _, _| selected = value[:id] })
    tree.expand(:root)
    render(tree)
    body = tree.root
    assert tree.select_id(19)
    render(tree)
    assert_equal 19, selected
    assert_equal 19, tree.selected_id
    assert_same body, tree.root
    tree.collapse(:root)
    assert tree.select_id(19)
    render(tree)
    assert_includes tree.expanded, :root
    assert_includes tree.root.visible_range, 20
    refute tree.select_id(:missing)
  end

  def test_virtual_table_accessibility_can_sort_headers_and_select_rows
    sorted, selected = nil, nil
    table = render(T::UI::VirtualTable.new(Source.new(10, [], false), columns: [:id], height: 100)
      .on_sort { |key, direction, _| sorted = [key, direction] }
      .on_select { |index, _, _| selected = index })
    header = @window.accessibility_tree.query(role: :columnheader).first.first
    row = @window.accessibility_tree.query(role: :row, states: {row_index: 1}).first.first
    assert T::Accessibility.perform(@window, header, :sort)
    assert_equal [:id, :asc], sorted
    assert T::Accessibility.perform(@window, row, :select)
    assert_equal 1, selected
    assert_equal Set[1], table.selection
  end

  def test_viewport_resize_keeps_virtual_panes_and_scroll_positions
    source = Source.new(100, [], false)
    table = render(T::UI::VirtualTable.new(source, columns: [:id], height: 100, row_height: 20))
    table.scroll_to(20)
    render(table)
    body, offset = table.body, table.body.scroll_y
    table.viewport_height = 180
    render(table)
    assert_same body, table.body
    assert_equal offset, table.body.scroll_y
    assert_equal 160, table.body.scroll_state.viewport_size.height
    table.follow_tail = true
    table.scroll_to(source.count - 1, align: :end)
    source.count += 10
    render(table)
    assert table.following_tail?
    table.follow_tail = false
    offset = table.body.scroll_y
    source.count += 10
    render(table)
    assert_equal offset, table.body.scroll_y

    hex = render(T::UI::HexView.new("bytes" * 1000, height: 100))
    hex.scroll_to_offset(1000)
    render(hex)
    body, offset = hex.body, hex.body.scroll_y
    hex.viewport_height = 180
    render(hex)
    assert_same body, hex.body
    assert_equal offset, hex.body.scroll_y
    assert_equal 180, hex.body.scroll_state.viewport_size.height

    tree = render(T::UI::TreeView.new(Array.new(100) { |i| {id: i, label: "#{i}"} }, height: 100))
    tree.select_id(50)
    render(tree)
    body, offset = tree.root, tree.root.scroll_y
    tree.viewport_height = 180
    render(tree)
    assert_same body, tree.root
    assert_equal offset, tree.root.scroll_y
    assert_equal 180, tree.root.scroll_state.viewport_size.height
    [table, hex, tree].each { |pane| assert_raises(ArgumentError) { pane.viewport_height = Float::NAN } }
  end
end
