# Contributing to Zaniah

Bug reports and focused pull requests are welcome. Please include the backend,
Ruby version, and a small reproduction when reporting a platform-specific issue.

## Local checks

Run these from the repository root before submitting a change:

```sh
bundle install
bundle exec rake test
bundle exec ruby tools/build_docs.rb --check
gem build --strict zaniah.gemspec
```

Run `bundle exec rake test:golden` for rendering changes and
`BUDGET=1 bundle exec rake bench` for performance-sensitive changes. Targeted
checks are available for the process pool, SVG/list behavior, and inspection API:

```sh
bundle exec ruby -Itest test/process_pool_test.rb
bundle exec ruby -Ilib -Itest test/svg_and_list_test.rb
bundle exec ruby -Itest test/inspection_contract_test.rb
```

## Documentation and previews

The Markdown files in `docs/` are the source for the [Pages guides](https://noxdea.github.io/zaniah/docs/guides/).
Edit those files, then validate them or build the local HTML preview:

```sh
bundle exec ruby tools/build_docs.rb --check
bundle exec ruby tools/build_docs.rb   # writes to tmp/site/docs/
```

The component API table in `docs/components.md` is also the source for the
component pages' API summaries. For visual changes, rebuild the galleries and
2× previews before regenerating the site:

```sh
bundle exec ruby tools/generate_component_gallery.rb
bundle exec ruby tools/generate_doc_previews.rb
bundle exec ruby tools/generate_component_gallery.rb ../docs/previews --docs-only --overlays-only
bundle exec ruby tools/build_docs.rb
```

## Platform and performance checks

Run native checks on the matching operating system and display server:

```sh
ruby examples/native_smoke.rb --check /tmp/zaniah.png
ruby examples/native_smoke.rb --gl --check /tmp/zaniah-gl.png
ruby examples/linux_smoke.rb
ruby examples/linux_smoke.rb --wayland
ruby examples/native_watch.rb
ruby examples/native_menu.rb              # macOS only
```

Linux XIM composition runs in CI with Xvfb and IBus/KKC. Native input, IME on
macOS and Windows, dialogs, and terminal integration also need manual checks on
their target operating system.

For text or grid performance work, use the relevant focused benchmarks:

```sh
BUDGET=1 ruby --yjit bench/text_frame.rb
ruby --yjit bench/atlas_startup.rb
BUDGET=1 ruby bench/grid.rb
ruby --yjit -Ilib bench/list.rb
```

`bench/grid.rb` measures a headless 800×600 viewport over a 1,000,000×16,000
grid at 23 scroll positions; its budget is a 16.67 ms median frame time. It
excludes application storage, expensive cell renderers, and native composition,
so rerun it on target hardware for deployment decisions. The optional shaping
oracle requires `hb-shape` and is not used at runtime:

```sh
ruby --yjit -Ilib script/shaper_oracle assets/fonts/Abel-Regular.ttf /path/to/font.ttf
```
