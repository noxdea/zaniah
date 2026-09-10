# Zaniah

A Ruby UI toolkit with native GPU windows, a headless renderer, and a terminal
backend. CRuby 3.1+; YJIT recommended. Runtime dependencies are Alhena, REXML
and unicode-display_width.

The name comes from the white ground laid before paint or gold leaf: this
toolkit is the drawing surface beneath the editor.

## Try it locally

```sh
bundle install
bundle exec rake test
ruby --yjit examples/native_smoke.rb
gem build zaniah.gemspec
gem install --local zaniah-0.1.0.gem
```

The gem name is not published or reserved. Install the locally built artifact
rather than an unverified public gem.

```ruby
require "zaniah"

window = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 240)
window.text_system = Zaniah::TextSystem::Renderer.new
window.draw do
  Zaniah::Div.new.flex_col.p(24).gap(12).bg("#161b22")
    .child(Zaniah::Text.new("Hello, Ruby", size: 24))
    .child(Zaniah::Text.new("A native toolkit, written in Ruby."))
end
window.tick
window.write_png("hello.png")
window.close
```

Choose `backend: :mac`, `:linux`, `:windows`, or `:tui` and call
`window.run` for an interactive window. Native rendering uses OS libraries via
Ruby's Fiddle, without extension compilation or a rendering subprocess.

## Toolkit and platforms

Flex layouts, constraints, absolute positioning, wrapping, baseline alignment,
clipping, retained element state, and uniform/variable-height virtual lists are
provided. Generational entities and subscriptions connect state to frames;
foreground Fibers can await background tasks without blocking the UI.
Scene primitives include rounded rectangles, images, static SVG, shadows and
glyph atlases. OpenType ligatures and horizontal positioning use the Ruby shaper.
Pure Ruby rasterization is the default; explicit CoreText/FreeType providers and
a licensed Abel fallback font are included.

## Development

```sh
bundle exec rake test
ruby --yjit bench/instances.rb
ruby --yjit bench/list.rb
```

`BUDGET=1` enables benchmark assertions.

See [native details](docs/native.md), [text configuration and shaping](docs/text.md),
[SVG and lists](docs/vector_and_list.md), [portable CPU workers](docs/process_pool.md),
and [decisions](docs/adr).

## License

MIT; see [LICENSE.txt](LICENSE.txt). Included font notices remain alongside the
font files.
