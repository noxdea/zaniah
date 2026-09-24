# Layout and scrolling

Zaniah uses flex layout by default. Set `display: :grid` for a bounded Grid
subset with explicit tracks, row-first automatic placement, spans, gaps, `fr`,
`minmax`, and `auto` tracks.

```ruby
include Zaniah::LengthUnits

Zaniah::Div.new.style(
  display: :grid,
  grid_template_columns: [px(120), fr(1), fr(2)],
  column_gap: 8
).children(items)
```

Place an item with `grid_column: 2` or span inclusive tracks with
`grid_column: 1..3`. Named areas and `auto-fit`/`auto-fill` are not supported.

`UI::PaneGrid` turns a rectangular matrix into independently resizable rows and
columns. Each non-empty cell is a `PaneGrid::Pane`, an `id`/`content` hash, or
an `[id, content]` pair. IDs must be unique and remain stable when `replace` is
used so retained pane state survives source rebuilds. Tracks accept fixed pixel
numbers, `px`, `fr`, or `minmax` values.

```ruby
grid = Zaniah::UI::PaneGrid.new(
  [[[:editor, editor], [:terminal, terminal]]],
  columns: [Zaniah.minmax(Zaniah.px(240), Zaniah.fr(2)), Zaniah.fr(1)],
  rows: [Zaniah.fr(1)]
)
grid.on_resize { |event, _context| save_split(event.axis, event.divider, event.before) }
```

Dividers support pointer drag, arrow keys, Page Up/Down, Home, and End. Their
stable accessibility IDs, focus state, value, orientation, and direct increment,
decrement, minimum, and maximum actions use the same clamped resize path. Nested
`PaneGrid` instances compose without owning editor, terminal, or document state.

## Two-axis virtual grid

`UI::Grid` virtualizes rows and columns independently. It uses estimated row and
column sizes for a large sheet, calling the size procs only for frozen and
visible cells. Use `frozen_rows` and `frozen_columns` for headers and key
columns; cell ranges are represented by half-open integer ranges.

```ruby
grid = Zaniah::UI::Grid.new(
  rows: 1_048_576, columns: 16_384,
  row_height: ->(row) { row.zero? ? 32 : 24 },
  column_width: ->(column) { column.zero? ? 180 : 96 },
  frozen_rows: 1, frozen_columns: 1
) do |row, column, bounds, cx|
  Zaniah::UI::Label.new("#{row},#{column}")
end

grid.on_select { |areas, _event, _cx| p areas }
grid.on_edit { |row, column, _event, _cx| edit_cell(row, column) }
grid.on_fill { |source, destination, _cx| fill_cells(source, destination) }
grid.on_resize { |axis, index, size, _cx| save_size(axis, index, size) }
```

The renderer returns an Element, String, Numeric, or `nil` for each visible
cell. `bounds` is local to the grid viewport. Set `estimated_row_height` or
`estimated_column_width` when proc-based sizes differ substantially from the
defaults. `scroll_to(row:, column:)` ensures the target cell is visible.
Resizing is available by dragging a visible cell's lower/right edge or by
calling `set_row_height` / `set_column_width`; explicit size overrides persist
when the virtualized viewport is rebuilt. `hide_row` / `unhide_row` and
`hide_column` / `unhide_column` set or restore an axis entry's size to zero;
indexes are validated against the grid and zero-sized entries are skipped by
offset lookup. `hide_rows(indices, hidden:)` and `hide_columns(indices, hidden:)`
apply a validated batch with a single frame request; `row_hidden?` and
`column_hidden?` report current state. Fill only reports the source and
destination areas; the application owns cell values and fill semantics. Shift
extends a range; Cmd/Ctrl-click toggles an additional cell range.

Copy and paste are opt-in: the grid never owns cell values. `on_copy` receives
the selected `Grid::Area` values and returns MIME-keyed content, which Zaniah
writes to the clipboard. `on_paste` receives the same half-open areas and all
available clipboard formats; the application decides how to apply them.
Without the corresponding hook, the action is unhandled. With a hook but no
selection, the action is disabled.

```ruby
grid.on_copy do |areas, _cx|
  {"text/plain" => cells_as_tsv(areas), "text/html" => cells_as_html(areas)}
end
grid.on_paste do |areas, content, _cx|
  paste_cells(areas, content.fetch("text/plain")) if content.types.include?("text/plain")
end
```

`UI::Table` and `UI::DataGrid` use the same hooks. Their existing `selection`
remains a set of stable row IDs; hook arguments are `Grid::Area` ranges in the
current sorted display order, covering all columns. Disjoint selected rows
produce separate areas. The application retains ownership of table data.

`bench/grid.rb` measures a headless 800×600 viewport over a 1,000,000×16,000
grid at 23 sequential scroll positions, including cell construction, layout,
prepaint, and paint. `BUDGET=1 ruby bench/grid.rb` asserts a 16.67 ms median
frame limit. A local run on 2026-09-23 measured 12.964 ms and constructed an
average of 250 cells per frame. This microbenchmark does not include an
application's backing store, expensive cell renderers, or a native compositor;
rerun it on target hardware for deployment decisions.

`ScrollView` accepts one child and clips it to the viewport. Its `axis` is
`:vertical`, `:horizontal`, or `:both`; use `scroll_to` for programmatic
scrolling and `scroll_state` for offsets and edge checks.

```ruby
view = Zaniah::ScrollView.new(axis: :vertical).w(320).h(240).child(content)
view.scroll_to(120)
```

`aspect_ratio` derives an unspecified dimension. Logical edge properties such
as `padding_start` and `margin_end` follow `direction: :ltr` or `:rtl`.
`position: :sticky` is effective inside a `ScrollView`.
