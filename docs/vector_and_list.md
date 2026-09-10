# Vector icons and variable-height lists

`SVG` and `List` are normal elements and participate in layout, clipping, hit
testing, and scene painting.

## Static SVG icons

```ruby
icon = Zaniah::SVG.open("assets/search.svg", color: "#d8e4f0").w(24).h(24)
icon = Zaniah::SVG.parse(
  '<svg viewBox="0 0 24 24"><path d="M4 12H20" stroke="currentColor"/></svg>'
)
```

The renderer supports SVG paths, basic shapes, groups, transforms, view boxes,
inherited fill and stroke, `currentColor`, opacity, local `defs`/`use`, and
user-space clip paths. It is intended for static icons, not arbitrary web SVG.

Scripts, external references, CSS stylesheets, gradients, filters, masks, images,
text, markers, dash arrays, nested viewports, and object-bounding-box clips are
unsupported and raise `ArgumentError`. Input is bounded to 2 MiB, 10,000 XML
nodes, 64 levels, and 100,000 path operations; each output texture is limited to
one megapixel.

## Variable-height lists

```ruby
rows = Zaniah::List.new(count: 1_000_000, estimated_height: 24, overscan: 2) do |index|
  Zaniah::Div.new
    .h(index.even? ? 20 : 28)
    .child(Zaniah::Text.new("Row #{index}"))
end.w(600).h(400)

rows.scroll_to(500_000, align: :center)
```

Give the list a viewport height. Only visible rows and the overscan margin are
instantiated; other rows retain estimated heights until measured. Persistent row
state belongs in keyed window state or the application model.

`scroll_y=` changes the pixel offset. `scroll_to(index, align:)` accepts `:start`,
`:center`, `:end`, and `:nearest`. `update_height` supplies a measurement before
rendering, `visible_range` returns the instantiated exclusive-end range, and
`total_height` includes estimates. A list's item count is fixed; create a new
list when the count changes.

See [the element declarations](../sig/elements.rbs) for the complete API. Run:

```sh
ruby -Ilib -Itest test/svg_and_list_test.rb
ruby --yjit -Ilib bench/list.rb
```
