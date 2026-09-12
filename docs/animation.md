# Animation

Zaniah uses one clock-driven `Animator` per window. Rendering stays idle when no
animation is active, and injected clocks keep headless tests deterministic.

```ruby
window.animator.animate(:progress, from: 0, to: 1,
  duration: 0.18, easing: :ease_out)
window.animator.value(:progress)
```

Available easing values are `linear`, `ease_in`, `ease_out`, and `ease_in_out`.
`Zaniah::Easing.cubic_bezier(x1, y1, x2, y2)` and
`window.animator.spring(key, to:, stiffness:, damping:, mass:)` cover custom
curves and spring motion. Numeric values, `Color`, same-unit `Length`, and
`Transform` values can be interpolated.

## Style transitions

```ruby
Div.new.key(:save).bg(theme.colors.surface)
  .hover(background: theme.colors.surface_hover)
  .transition(:background, duration: theme.motion.duration_base)
```

Transitions require `key`; without one the new style is applied immediately.
Keyed children of a stable `Div` or `List` automatically animate additions,
removals, and position changes. Removed children remain paintable in the
window's existing element-state store until their exit animation completes.

`ScrollView`, `List`, and `UniformList` use the same animator for inertial
scrolling. Pass `inertia: false` to a standalone `ScrollState` to disable it.
Overlay scrollbars fade after activity; modal overlays and collapsible content
animate visibility. Editable text carets, skeletons, and spinners also use the
window clock.

## Reduced motion

The macOS, Windows, and Linux backends read the operating-system reduced-motion
setting. When `theme.motion.reduced?` is true, the animator completes every
animation immediately. Tests or applications can opt in explicitly:

```ruby
theme = Theme.dark
app.global(:theme, theme.with(motion: theme.motion.with(reduced: true)))
```
