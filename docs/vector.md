# Vector recording

Zaniah records the drawing it already performs without taking ownership of PDF
pages, paper sizes, or export dialogs. Require `zaniah/vector` and render a normal
element tree offscreen:

```ruby
document = Zaniah::Vector.record(width: 960, height: 540,
  theme: Zaniah::Theme.light) { slide }
document.commands.each { |command| export_command(command) }
```

To inspect a displayed frame, attach a recorder before rendering. `Scene#clear`
resets its commands each frame; save `recorder.document` before the next frame.

```ruby
recorder = Zaniah::Vector::Recorder.new
window.scene.vector_sink = recorder
window.tick
document = recorder.document
window.scene.vector_sink = nil
```

`Document#width` and `#height` are logical pixels. A `Recorder` attached to a
window receives that window's content size; a recorder attached to a bare
`Scene` may instead be initialized with `width:` and `height:`. Coordinates use
a top-left origin and downward y axis; colors are sRGB. Every command carries
its transform, clip, opacity, layer, and sequence. `Document#commands` is sorted
by layer and then sequence, matching `Scene#each_command`.

| Command | Export information |
|---|---|
| `Quad` | Bounds, fill color or gradient, corner radii, border widths/color/style |
| `Shadow` | Bounds, corner radii, color, blur, spread, inset |
| `Path` | Alhena outline, fill, stroke, stroke width, fill rule and stroke cap/join |
| `GlyphRun` | Alhena font, size, `[glyph_id, x, baseline_y]` triples, original text and UTF-8 byte clusters |
| `Image` | Decoded `Zaniah::Image`, bounds and source rectangle, plus a frozen pixel snapshot |
| `Underline` | Position, thickness and wave flag |
| `Raster` | Frozen source texture bytes, pixel dimensions/format, tint and source rectangle |

Ordinary sprites and packed sprite batches become `Raster`; bitmap-color text
uses that fallback for the whole line. Simple SVG fills and strokes become
`Path` commands. SVG clipping, gradients, dash arrays, masks, group opacity,
and references use a `Raster`
fallback, so they are not silently omitted. The `Raster` bytes are a snapshot
at recording time, even if the source texture changes later. The converter must
crop to `source`, apply `color` and `opacity`, then respect `transform` and
`clip`. It may rasterize a `Path` or `GlyphRun` when its output format lacks
an equivalent vector primitive.

The headless offscreen API works on every OS and does not require a GPU.
Attaching a recorder to macOS, Windows, X11, or Wayland uses the same `Scene`
path. The TUI backend captures its terminal cells as a single `Raster` fallback
at an 8-by-20 cell grid, using a bundled font approximation; terminal font
appearance is outside Zaniah's control. Use the offscreen API when scalable
text is required.

See [ADR 016](adr/016-semantic-vector-recording.md) for why this is separate
from the GPU command stream. [Vector and list](vector_and_list.md) documents
the SVG input subset.
