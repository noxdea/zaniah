# Changelog

## 0.8.0 — 2026-09-24

- Add native macOS and Windows menus, declarative context menus, and platform-aware shortcut labels.
- Add MIME-keyed clipboard content on desktop backends, including HTML, PNG, file URLs, and X11 incremental transfers.
- Add Grid and Table copy/paste hooks with TSV and HTML data.
- Add window state persistence, frameless windows, and draggable title regions across native backends.

## 0.7.0 — 2026-09-24

- Add a stable frame inspection API with accessibility queries and DevTools integration.
- Unify focused and application commands with validation, availability, and checked state.
- Add headless and TUI clipboard support, including OSC 52 output.
- Add desktop editing shortcuts and copy, cut, paste, undo, and redo for plain and rich text while leaving conflicting TUI shortcuts unbound.
- Add configurable matching and accessible, highlighted results to the command palette and combobox.

## 0.6.4 — 2026-09-24

- Share Cartesian chart scales, axes, grid lines, ticks, and color-keyed legends across chart types.

## 0.6.3 — 2026-09-23

- Render supplied text grid cells directly as cell surfaces, avoiding an extra wrapper per visible cell.
- Add a two-axis virtualized UI grid with frozen panes, range selection, variable sizing, resize, and fill callbacks.
- Preserve explicit grid row/column sizes across viewport rebuilds and support validated, batched row/column hide and unhide.
- Add editable rich text with style spans, paragraph alignment/lists, selection, caret, and IME composition.
- Decode baseline 8-bit JPEG images, including Exif orientation, grayscale, RGB, and common YCbCr sampling modes; detect JPEG images from bytes.
- Allow Alhena 0.3 while retaining compatibility with the existing Alhena 0.2 API.

## 0.6.2 — 2026-09-21

- Add GIF decoding and a damage-aware terminal grid view.

## 0.6.1 — 2026-09-21

- Add a deterministic headless demo image and regeneration task.

## 0.6.0 — 2026-09-19

- Add the validated declarative Describe layer for remote UI trees, including event routing, tree diffs, keyed surface reuse, and element descriptions.

## 0.5.3 — 2026-09-17

- Restore Ruby 4.0/json 3 compatibility for process messages and atlas caches while keeping JSON object additions disabled.

## 0.5.2 — 2026-09-16

- Preserve insertion order for inline overlays that share an offset and alignment.

## 0.5.1 — 2026-09-16

- Let lazy tree views accept externally loaded children and invalidate cached subtrees without blocking the UI thread.
- Prevent replacement tree sources from inheriting stale lazy children.

## 0.5.0 — 2026-09-15

- Make tree views lazy and viewport-virtualized while preserving stable-ID state across source rebuilds.
- Add bounded, thread-safe low-resolution text textures with per-line invalidation and repeated-shape raster reuse for minimaps.
- Add stable-ID pointer and keyboard reordering with virtual targets and live accessibility status.
- Add arbitrary stable-ID pane grids with resizable fixed, fractional, and minmax tracks.
- Preserve screen-reader identity across virtualization and reordering, with direct tree and pane actions plus native focus and live-region events.

## 0.4.0 — 2026-09-15

- Add inline and block text overlays with wrapping-aware layout, hit testing, and row-local relayout.

## 0.3.0 — 2026-09-14

- Improve large flex layouts, GPU scene submission, and software-rendered gradients for smoother frames.
- Add dark, light, and high-contrast themes with immediate hover, active, focus, and disabled styling.
- Add Grid, ScrollView/ScrollState, sticky and logical layout, spatial focus navigation, and platform cursors.
- Add gradients, transforms, paths, layered effects, and matching Software, OpenGL, Metal, and Vulkan scene rendering.
- Add paragraph layout, Japanese kinsoku, font fallback, selection, Unicode-safe editing, and native IME composition.
- Add the opt-in `zaniah/ui` component library with keyboard and TUI support.
- Add clock-driven animation, keyed transitions, inertial scrolling, and reduced-motion support.
- Add virtual data views, charts, validated forms, native screen-reader support on macOS, Windows, and Linux, DevTools, and a three-theme component gallery.

## 0.2.0 — 2026-09-11

- Add read-only element, hit-region, popup, and frame inspection APIs.
- Add injectable monotonic clocks and headless-window keymaps.
- Keep adjacent compact text rows separate in the TUI renderer.

## 0.1.0 — 2026-09-11

- Initial release.
