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

Providers may implement `close`; the text system closes them when it closes.
Custom mutable providers used by `fork` must also implement `layout_copy` and
return an independent provider.

The default Ruby shaper supports horizontal Latin, CJK, and kana text, including
common OpenType ligatures, contextual substitutions, pair positioning, and
legacy kerning. It is not a replacement for full complex-script shaping:
Arabic/Indic reordering, AAT `morx`, vertical text, complete mark positioning,
and variation-index positioning are unsupported.

Built-in rasterizers are `:native`/`:alhena`, `:freetype`, and `:coretext`
(`:core_text` is an alias). FreeType and CoreText require their platform library.
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

## Development checks

```sh
BUDGET=1 ruby --yjit bench/text_frame.rb
ruby --yjit bench/atlas_startup.rb
ruby --yjit -Ilib script/shaper_oracle assets/fonts/Abel-Regular.ttf /path/to/font.ttf
```

The shaping oracle is optional and requires `hb-shape`; it is not used at runtime.
