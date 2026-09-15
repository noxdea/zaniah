# Changelog

## Unreleased

- Make tree views lazy and viewport-virtualized while preserving stable-ID state across source rebuilds.
- Add bounded, thread-safe low-resolution text textures with per-line invalidation for minimaps.
- Add stable-ID pointer and keyboard reordering with virtual targets and live accessibility status.

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
