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
