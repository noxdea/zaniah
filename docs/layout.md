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
