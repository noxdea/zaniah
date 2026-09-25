# Text system

`TextSystem::Renderer` provides layout, glyph rasterization, atlas management, and
painting. `TextSystem::Typesetter` provides layout and caret measurements without
allocating glyph textures.

```ruby
db = Zaniah::TextSystem::FontDB.new
font = db.find(family: "Menlo", weight: 700, width: 5, style: :normal)
system = Zaniah::TextSystem::Renderer.new(font: font, font_db: db)
window.text_system = system
```

`FontDB` discovers TTF, OTF, TTC, and OTC fonts in platform directories. It
selects faces by family, weight (`1..1000`), width (`1..9`), and style
(`:normal`, `:italic`, or `:oblique`). A bundled Abel font is the final fallback.
Call `refresh` to clear cached discovery results.

## Providers and shaping

Defaults can be configured globally or supplied to a constructor:

```ruby
Zaniah.configure do |config|
  config.font_db = :native
  config.shaper = :native
  config.segmenter = :native
  config.font_raster = :native
end
```

Provider objects may be supplied instead of symbols:

| Setting | Required method | Result |
| --- | --- | --- |
| `font_db` | `find(...)`, `fallback(codepoint, primary_font)` | A font compatible with Alhena |
| `shaper` | `shape(glyphs, size:, text:)` | `Array[TextSystem::Glyph]` with UTF-8 byte clusters |
| `segmenter` | `grapheme_clusters(text)` | Strings that exactly partition the input |
| `font_raster` | `rasterize(font, glyph_id, size:, subpixel_x:)` | A glyph bitmap |

Shapers may additionally accept `script:`, `language:`, `direction:`,
`features:`, and `writing_mode:`. The typesetter inspects accepted keywords, so an existing
`shape(glyphs, size:, text:)` provider remains valid. If a provider does not
accept `direction:`, a right-to-left run is shaped in storage order and its
glyphs are reversed for display. Hebrew works with this fallback; Arabic
joining in a legacy provider still requires a direction-aware shaper. The built-in shaper
accepts `direction: :ltr/:rtl` and a four-character OpenType feature map such
as `{"liga" => false}`.

Providers may implement `close`; the text system closes them when it closes.
Custom mutable providers used by `fork` must also implement `layout_copy` and
return an independent provider.

The default Ruby shaper supports horizontal Latin, CJK, and kana text, including
common OpenType ligatures, contextual substitutions, pair positioning, and
legacy kerning. For Arabic-script OpenType fonts with GSUB, it selects
`isol`/`fina`/`medi`/`init` from Unicode 18 Joining_Type and then applies
`rlig`; transparent marks and ZWJ/ZWNJ affect joining. The input `text:` is
needed to select forms. Fonts using AAT `morx` (including some macOS Arabic
fonts), advanced Arabic substitutions, complete mark and cursive positioning,
Indic reordering, complete vertical GPOS positioning, and variation-index
positioning still need an external shaper. The bundled Abel font has no Arabic
glyphs. Vertical layout uses `vmtx` advances and GSUB `vert`/`vrt2` where
available; fonts without vertical metrics retain horizontal advances.

Built-in rasterizers are `:native`/`:alhena`, `:freetype`, `:coretext`
(`:core_text` is an alias), and Windows-only `:directwrite` (`:direct_write`
is an alias). FreeType, CoreText, and DirectWrite require their platform library.
DirectWrite remains opt-in; Windows still defaults to `:native`. It loads fonts
opened by `FontDB` from their file paths, and other in-memory fonts through the
Windows 10 in-memory font loader. Its default atlas bitmap is grayscale;
`Platform::Windows::DirectWrite#rasterize(..., antialias: :cleartype)` returns
an RGB coverage bitmap for callers that can display subpixel coverage. Compare
it with Alhena using `ruby examples/native_font.rb path/to/font.ttf --directwrite`
on Windows. Variable-font instances with selected axes use Alhena's rasterizer
until an axis-aware DirectWrite face is available. Close an explicitly created
DirectWrite provider when finished.
Unimplemented symbolic adapters raise `ArgumentError`; pass a provider object to
integrate another shaper, segmenter, font database, or rasterizer.

## Background layout and startup cache

Create an independent layout-only typesetter for background work:

```ruby
typesetter = system.fork(capacity: 32)
# use typesetter on one background worker
typesetter.close
```

Do not mutate one text system or atlas concurrently. Font bytes may be shared,
but mutable providers and caches must be copied.

Disk-backed atlas caching is opt-in. Prewarm only after the window scale is known:

```ruby
system = Zaniah::TextSystem::Renderer.new(cache_dir: "/path/to/app-cache/glyphs")
system.scale_factor = window.scale_factor
system.prewarm(size: 14)
window.text_system = system
```

A missing, corrupt, or read-only cache does not prevent rendering. Applications
own cache-directory retention. See [the RBS declarations](../sig/text.rbs) for
the complete API.

For minimaps and other compact previews, cache Alhena's downsampled outlines as
one R8 texture per source line:

```ruby
cache = Zaniah::TextSystem::LowResolutionTextCache.new(
  width: 100, height: 2, scale: 0.1
)
texture = cache.texture(42, outlines: outlines)
cache.invalidate(42) # regenerate only the edited source line on next access
cache.close
```

The cache is thread-safe, count- and byte-bounded, and uses least-recently-used
eviction. Textures already returned to a scene remain valid after eviction or
invalidation. A cache has fixed width, height, and scale; invalidate a line when
its outlines change for any reason, including a font change. Call `close` when
the cache is no longer needed.

## Paragraphs, selection, and editing

Single-line layout remains the default. Enable wrapping explicitly on a `Text`
element or construct a paragraph for layout-only work:

```ruby
text = Zaniah::Text.new("長い文章…", wrap: :word, line_height: 1.5,
  letter_spacing: 0.2, align: :start, kinsoku: :push).w(320)

paragraph = system.layout_paragraph("Text", width: 320, wrap: :word)
offset = paragraph.hit_test(Zaniah::Point.new(40, 20))
point = paragraph.offset_to_point(offset)
```

Bidirectional text uses Unicode 18.0's UAX #9 rules, with Unicode tables
generated by `tools/generate_unicode_tables.rb` and no runtime data download.
`Text.new(value, text_direction: :auto)` detects paragraph direction; use
`:ltr` or `:rtl` to override it. Layout-only callers may pass `direction:`
to `layout_paragraph` or `layout_line`. `align: :start/:end` follows paragraph
direction. Text remains in logical UTF-8 byte order for editing and copying.

At a boundary between directional runs, the same byte offset can have two
screen positions. `LineLayout#caret_x(offset, affinity: :downstream)` chooses
one, and `LineLayout#hit_test(x)` returns `[offset, affinity]`. The old
`x_for_index` and `index_for_x` methods remain available for callers that do
not retain affinity. `selection_rects(range)` returns the visual rectangles
occupied by a logical range. `Text.new(..., caret_movement: :logical)` opts
out of the default visual left/right arrow movement.

Vertical Japanese layout is opt-in. The `width:` argument to a vertical
paragraph is its inline (top-to-bottom) limit; columns advance right to left.
On `Text`, use `.h(...)` for that limit:

```ruby
paragraph = system.layout_paragraph("縦書き", width: 240,
  writing_mode: :vertical_rl)
text = Zaniah::Text.new("縦書き", writing_mode: :vertical_rl,
  text_orientation: :mixed).h(240)
```

`text_orientation: :mixed` keeps CJK glyphs upright and rotates ordinary Latin
letters and digits 90 degrees. `:upright` keeps all glyphs upright. Hit testing,
caret, selection, composition underline, and IME bounds use vertical geometry;
offsets and clipboard text stay in logical UTF-8 byte order. This is a
lightweight vertical layout, not a complete CSS Writing Modes implementation:
it does not implement `VORG`, vertical kerning/mark positioning, script-specific
vertical baseline adjustment, or arbitrary sideways writing modes. Font support
determines whether vertical glyph substitutions and metrics are available.

Wrapping supports `:none`, `:word`, and `:anywhere`; Japanese kinsoku modes are
`:push`, `:hanging`, and `:none`. Font fallback is selected per grapheme from the
requested font through CJK, emoji, symbol, and general system faces. Colored
COLR, CBDT, and sbix glyphs use the RGBA atlas.

Use `selectable` for pointer/keyboard selection and `editable` for a UTF-8 text
buffer with undo, redo, grapheme-safe changes, and IME composition:

```ruby
buffer = Zaniah::TextBuffer.new("hello")
field = Zaniah::Text.new(buffer.to_s).editable(buffer)

buffer.insert(buffer.bytesize, " 👋")
buffer.undo.redo
```

Offsets are UTF-8 byte offsets and edits must land on extended grapheme-cluster
boundaries. The string-backed buffer is intended for ordinary fields and
documents up to tens of thousands of characters; a piece table is deliberately
outside the current scope.

`UI::RichText` manages a single text buffer with disjoint style spans. Its
editing API uses UTF-8 byte ranges, and its surface lays out mixed-size runs on
shared wrapped lines. Editable input is opt-in to preserve the old read-only
component behavior:

```ruby
text = Zaniah::UI::RichText.new([
  {text: "Quarterly ", bold: true},
  {text: "report", italic: true, color: "#2563eb", size: 22}
], editable: true).w(480)

text.apply(0...10, color: "#2563eb")
text.insert(text.text.bytesize, " — draft")
text.paragraph_style(0...text.text.bytesize, align: :start, list: :bullet, level: 0)
```

Supported inline styles include `bold`, `italic`, `size`, `color`, `font`,
`link`, decoration/background styles, `ruby:`, and `combine_upright:`.
`ruby: "reading"` annotates one unbreakable parent run; copying selects only
the parent text, while accessibility and TUI readings include the annotation
in parentheses. `combine_upright: true` keeps a short run such as `12` upright
inside vertical text. Ruby and combine-upright cannot be combined on one run.

```ruby
rich = Zaniah::UI::RichText.new([
  {text: "漢字", ruby: "かんじ"},
  {text: "12", combine_upright: true}
], writing_mode: :vertical_rl).h(240)
```

Paragraph styles support `align: :start/:center/:end/:justify`,
`list: :none/:bullet/:ordered`, and nonnegative nesting levels. `on_change`
receives `(text, rich_text)`; selection changes are reported by `on_select`.
IME composition uses the existing `TextBuffer` composition path.

## Editing shortcuts

Editable text fields and rich text share the same actions from keyboard, menu,
and command dispatch. The default desktop keys are:

| Action | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Undo / redo | Cmd+Z / Cmd+Shift+Z | Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z | Ctrl+Z / Ctrl+Shift+Z |
| Cut / copy / paste / select all | Cmd+X/C/V/A | Ctrl+X/C/V/A | Ctrl+X/C/V/A |
| Previous / next word | Option+Left/Right | Ctrl+Left/Right | Ctrl+Left/Right |
| Document start / end | Cmd+Up/Down | Ctrl+Home/End | Ctrl+Home/End |

Shift with a word arrow extends the selection. Up/Down moves between logical
lines in multiline fields; Home/End moves to the current line's edges. Copy
requires a selection, and password fields never copy or cut. Paste and undo
are disabled during IME composition. The TUI does not assign these desktop
editing shortcuts by default because terminal control keys can conflict;
applications may provide a custom keymap.

## Inline and block overlays

Attach non-editable UI elements to text without inserting bytes into the source:

```ruby
hint = Zaniah::Div.new.w(72).h(20).bg("#334155").on_click { show_type_help }
code_lens = Zaniah::Div.new.h(20).child(Zaniah::Text.new("3 references"))

text = Zaniah::Text.new(source, wrap: :word)
  .inline_overlay(offset: 42, element: hint, align: :after)
  .block_overlay(line: 10, element: code_lens, position: :above, height: 20)
```

Inline overlay width participates in wrapping. `align: :after` keeps the logical
caret before the overlay; `:before` keeps it after the overlay. Block line numbers
are zero-based. Overlay elements receive pointer events but are never part of text
selection. Use `hit_test(point)` and `offset_to_point(offset)` for local display ↔
UTF-8 byte-offset conversion, and `remove_overlay(element)` to detach an overlay.
