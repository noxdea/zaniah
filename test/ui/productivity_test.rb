# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class ProductivityComponentsTest < Minitest::Test
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
    component
  end

  def test_grid_virtualizes_both_axes_and_keeps_frozen_panes
    rendered = []
    grid = T::UI::Grid.new(rows: 1_000_000, columns: 16_000, frozen_rows: 1, frozen_columns: 1,
      row_height: ->(row) { row.zero? ? 30 : 20 }, column_width: ->(column) { column.zero? ? 80 : 100 }) do |row, column, bounds, _cx|
      rendered << [row, column, bounds]
      "#{row},#{column}"
    end.w(320).h(160)

    render(grid)
    assert_operator rendered.length, :<, 100
    assert_includes rendered.map { |row, _, _| row }, 0
    assert_includes rendered.map { |_, column, _| column }, 0
    assert_operator grid.visible_rows.size, :<, 20
    assert_operator grid.visible_columns.size, :<, 10

    grid.scroll_to(row: 50_000, column: 3_000)
    render(grid)
    assert grid.visible_rows.cover?(50_000)
    assert grid.visible_columns.cover?(3_000)
    assert_operator grid.scroll_state.offset.y, :>, 0
    assert_operator grid.scroll_state.offset.x, :>, 0
  end

  def test_grid_freeze_panes_can_change_after_construction
    rendered = []
    grid = T::UI::Grid.new(rows: 100, columns: 100, row_height: 20, column_width: 50) do |row, column, _bounds, _cx|
      rendered << [row, column]
      "#{row},#{column}"
    end.w(240).h(120)
    render(grid)
    grid.scroll_to(row: 20, column: 10)
    render(grid)
    rendered.clear

    assert_same grid, grid.freeze_panes(rows: 2, columns: 1)
    assert @window.dirty?
    render(grid)
    assert_includes rendered, [0, 0]
    assert_operator grid.visible_rows.begin, :>=, 2
    assert_operator grid.visible_columns.begin, :>=, 1

    assert_raises(ArgumentError) { grid.freeze_panes(rows: 101, columns: 1) }
    assert_raises(ArgumentError) { grid.freeze_panes(rows: 1, columns: -1) }
    assert_equal [2, 1], [grid.instance_variable_get(:@frozen_rows), grid.instance_variable_get(:@frozen_columns)]
  end

  def test_grid_uses_text_cells_as_the_cell_surface
    text = T::Text.new("cell", wrap: :none)
    grid = T::UI::Grid.new(rows: 1, columns: 1) { text }.w(120).h(40)

    render(grid)

    assert_equal :relative, text.parent.resolved_style[:position]
    assert_equal 1, grid.visible_rows.size
    assert_equal 1, grid.visible_columns.size
    assert_equal grid.instance_variable_get(:@cx).theme.colors.surface, text.resolved_style[:background]

    @window.input(T::Input::MouseDown.new(T::Point.new(10, 10), :left, [], 1))
    @window.input(T::Input::MouseUp.new(T::Point.new(10, 10), :left, []))

    assert_equal [T::UI::Grid::Area.new(rows: 0...1, columns: 0...1)], grid.selection
  end

  def test_grid_resize_overrides_survive_virtualized_builds_and_hide_cycles
    rendered = {}
    grid = T::UI::Grid.new(rows: 100, columns: 100,
      row_height: ->(row) { 10 + row }, column_width: ->(column) { 20 + column }) do |row, column, bounds, _cx|
      rendered[[row, column]] = bounds
      "#{row},#{column}"
    end.w(100).h(60)

    grid.set_row_height(1, 40).set_column_width(1, 50)
    render(grid)
    assert_equal 40.0, rendered.fetch([1, 0]).height
    assert_equal 50.0, rendered.fetch([0, 1]).width

    grid.scroll_to(row: 20, column: 20)
    render(grid)
    grid.scroll_to(row: 0, column: 0)
    rendered.clear
    grid.hide_row(1).hide_column(1)
    render(grid)
    refute rendered.keys.any? { |row, _column| row == 1 }
    refute rendered.keys.any? { |_row, column| column == 1 }

    grid.unhide_row(1).unhide_column(1)
    rendered.clear
    render(grid)
    assert_equal 40.0, rendered.fetch([1, 0]).height
    assert_equal 50.0, rendered.fetch([0, 1]).width

    assert_same grid, grid.hide_row(1).hide_row(1).unhide_row(1).unhide_row(1)
  end

  def test_grid_hide_apis_validate_axis_indexes
    grid = T::UI::Grid.new(rows: 2, columns: 3) { "cell" }
    [-1, 2, 1.0].each do |index|
      assert_raises(IndexError) { grid.hide_row(index) }
      assert_raises(IndexError) { grid.unhide_row(index) }
    end
    [-1, 3, 1.0].each do |index|
      assert_raises(IndexError) { grid.hide_column(index) }
      assert_raises(IndexError) { grid.unhide_column(index) }
    end
    assert_raises(ArgumentError) { grid.set_row_height(0, 0) }
    assert_raises(ArgumentError) { grid.set_column_width(0, -1) }

    requests = Struct.new(:count) do
      def request_frame = (self.count += 1)
    end.new(0)
    grid.instance_variable_set(:@cx, Struct.new(:window).new(requests))
    assert_same grid, grid.hide_rows([0, 1, 1], hidden: true)
    assert_equal 1, requests.count
    assert grid.row_hidden?(0)
    assert grid.row_hidden?(1)

    assert_raises(IndexError) { grid.hide_rows([0, 2], hidden: false) }
    assert grid.row_hidden?(0), "batch validation must finish before changing state"
    assert_equal 1, requests.count
    assert_raises(ArgumentError) { grid.hide_rows([0], hidden: :yes) }

    grid.hide_rows([0, 1], hidden: false)
    assert_equal 2, requests.count
    refute grid.row_hidden?(0)
    grid.hide_columns([0, 2], hidden: true)
    assert_equal 3, requests.count
    assert grid.column_hidden?(2)
  end

  def test_grid_range_selection_keyboard_navigation_and_resize
    resized = []
    grid = T::UI::Grid.new(rows: 20, columns: 20) { |row, column, _bounds, _cx| "#{row},#{column}" }
      .w(240).h(120).on_resize { |axis, index, size, _cx| resized << [axis, index, size] }
    render(grid)
    @window.input(T::Input::MouseDown.new(T::Point.new(40, 10), :left, [], 1))
    @window.input(T::Input::MouseUp.new(T::Point.new(40, 10), :left, []))
    assert_equal [T::UI::Grid::Area.new(rows: 0...1, columns: 0...1)], grid.selection
    @window.input(T::Input::MouseDown.new(T::Point.new(130, 10), :left, [:ctrl], 1))
    @window.input(T::Input::MouseUp.new(T::Point.new(130, 10), :left, [:ctrl]))
    assert_equal [T::UI::Grid::Area.new(rows: 0...1, columns: 0...1), T::UI::Grid::Area.new(rows: 0...1, columns: 1...2)], grid.selection
    @window.input(T::Input::MouseDown.new(T::Point.new(130, 10), :left, [:ctrl], 1))
    @window.input(T::Input::MouseUp.new(T::Point.new(130, 10), :left, [:ctrl]))
    assert_equal 1, grid.selection.length
    @window.input(T::Input::MouseDown.new(T::Point.new(40, 10), :left, [], 1))
    @window.input(T::Input::MouseUp.new(T::Point.new(40, 10), :left, []))
    @window.input(T::Input::KeyDown.new("shift-right", false))
    assert_equal T::UI::Grid::Area.new(rows: 0...1, columns: 0...2), grid.selection.first

    @window.input(T::Input::MouseDown.new(T::Point.new(95, 10), :left, [], 1))
    @window.input(T::Input::MouseMove.new(T::Point.new(115, 10), []))
    @window.input(T::Input::MouseUp.new(T::Point.new(115, 10), :left, []))
    assert_equal :column, resized.last&.first
    assert_equal 0, resized.last&.[](1)
    assert_equal 116.0, grid.instance_variable_get(:@column_index)[0]
  end

  def test_grid_fill_handle_reports_source_and_destination_ranges
    fills = []
    grid = T::UI::Grid.new(rows: 20, columns: 20) { |row, column, _bounds, _cx| "#{row},#{column}" }
      .w(240).h(120).on_fill { |source, destination, _cx| fills << [source, destination] }
    render(grid)
    @window.input(T::Input::MouseDown.new(T::Point.new(40, 10), :left, [], 1))
    @window.input(T::Input::MouseUp.new(T::Point.new(40, 10), :left, []))
    render(grid)
    @window.input(T::Input::MouseDown.new(T::Point.new(92, 20), :left, [], 1))
    @window.input(T::Input::MouseMove.new(T::Point.new(140, 50), []))
    @window.input(T::Input::MouseUp.new(T::Point.new(140, 50), :left, []))
    assert_equal [T::UI::Grid::Area.new(rows: 0...1, columns: 0...1), T::UI::Grid::Area.new(rows: 0...3, columns: 0...2)], fills.last
  end

  def test_rich_text_range_edits_merge_spans_and_preserve_utf8_boundaries
    rich = T::UI::RichText.new([{text: "A👩‍💻B", bold: true}])
    rich.apply(1...12, color: "#f00")
    assert_equal [{text: "A", bold: true}, {text: "👩‍💻", bold: true, color: "#f00"}, {text: "B", bold: true}], rich.runs
    assert_raises(ArgumentError) { rich.apply(2...3, italic: true) }

    rich.insert(13, "!")
    assert_equal "A👩‍💻B!", rich.text
    assert_equal({bold: true}, rich.spans.last.style)
    rich.delete(1...12)
    assert_equal "AB!", rich.text
    assert_equal [{text: "AB!", bold: true}], rich.runs
  end

  def test_rich_text_applies_styles_to_plain_text_and_insertion_splits_spans
    rich = T::UI::RichText.new("plain text")
    rich.apply(0...5, bold: true)
    assert_equal [{text: "plain", bold: true}, {text: " text"}], rich.runs
    rich.apply(7...8, italic: true)
    assert_equal [{text: "plain", bold: true}, {text: " t"}, {text: "e", italic: true}, {text: "xt"}], rich.runs

    styled = T::UI::RichText.new([{text: "abcd", bold: true}])
    styled.insert(2, "X", style: {italic: true})
    assert_equal [{text: "ab", bold: true}, {text: "X", italic: true}, {text: "cd", bold: true}], styled.runs
    assert_equal [[0, 2], [2, 3], [3, 5]], styled.spans.map { |span| [span.start, span.finish] }
  end

  def test_rich_text_replace_paragraph_styles_ime_and_mixed_style_rendering
    rich = T::UI::RichText.new([{text: "Hello ", bold: true}, {text: "world", size: 24, color: "#f00"}], editable: true).w(180)
    rich.paragraph_style(0...11, list: :bullet, level: 1, align: :center)
    rich.replace(6...11, "東京", style: {italic: true})
    assert_equal "Hello 東京", rich.text
    assert_equal :bullet, rich.paragraph_styles.first[:list]
    assert_equal [{text: "Hello ", bold: true}, {text: "東京", italic: true}], rich.runs

    render(rich)
    assert_equal "Hello 東京", @window.text_runs.map { |run| run[2] }.join
    @window.input(T::Input::MouseDown.new(T::Point.new(30, 8), :left, [], 1))
    rich.selection = T::TextSelection.new(6)
    @window.input(T::Input::Composition.new("日", [3, 0]))
    render(rich)
    assert_equal "Hello 日東京", @window.text_runs.map { |run| run[2] }.join
    refute_nil @window.ime_state
    @window.input(T::Input::TextInput.new("日"))
    assert_equal "Hello 日東京", rich.text
  end

  def test_rich_text_justifies_nonfinal_paragraph_lines
    rich = T::UI::RichText.new("one two three four five six").w(80)
    rich.paragraph_style(0...rich.text.bytesize, align: :justify)
    render(rich)
    lines = rich.root.instance_variable_get(:@lines)
    assert_operator lines.length, :>, 1
    assert_in_delta 80, lines.first.width, 0.01
    assert_operator lines.last.width, :<, 80
  end

  def test_rich_text_composition_replaces_selected_text_in_preview_and_commit
    rich = T::UI::RichText.new("ABCD", editable: true)
    render(rich)
    @window.input(T::Input::MouseDown.new(T::Point.new(5, 5), :left, [], 1))
    @window.input(T::Input::MouseUp.new(T::Point.new(5, 5), :left, []))
    rich.selection = T::TextSelection.new(1, 3)
    @window.input(T::Input::Composition.new("日", [3, 0]))
    render(rich)
    assert_equal "A日D", @window.text_runs.map { |run| run[2] }.join
    @window.input(T::Input::TextInput.new("日"))
    assert_equal "A日D", rich.text
  end
end
