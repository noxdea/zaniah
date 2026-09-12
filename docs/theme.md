# Themes and state styles

`Zaniah::Theme.dark`, `.light`, and `.high_contrast` provide semantic color,
spacing, radius, shadow, typography, and motion tokens. `App` installs the dark
theme by default and follows native window appearance changes. Read the active
theme with `FrameContext#theme` or `EntityContext#theme`.

```ruby
theme = cx.theme
card = Zaniah::Div.new.bg(theme.colors.surface).p(theme.spacing[4])
```

State styles resolve in this order, with later states winning:
`selected`, `hover`, `active`, `focus`, `focus_visible`, `disabled`.

```ruby
Zaniah::Div.new
  .bg(theme.colors.surface)
  .hover { |style| style.bg(theme.colors.surface_hover) }
  .active { |style| style.bg(theme.colors.surface_pressed) }
  .disabled { |style| style.opacity(0.5) }
```

Create a custom theme by constructing `Theme` with the same token value objects.
Public token names are semantic; applications should not depend on the built-in
themes' raw color values.

## Token groups

- `colors`: background/surface states, border/focus, text, accent, status,
  overlay, selection, and ring colors.
- `spacing`: a compact 4-pixel scale indexed by token number.
- `radii` and `shadows`: semantic `none`, `sm`, `md`, `lg`, and `full` values.
- `typography`: sans/mono families, six sizes, four weights, and three line heights.
- `motion`: fast/base/slow durations, easing names, and `reduced?`.

Records support `with`, so a local override does not mutate the shared theme:

```ruby
base = Zaniah::Theme.light
quiet = base.with(
  colors: base.colors.with(accent: Zaniah::Color.parse("#245b9b")),
  motion: base.motion.with(reduced: true)
)
app.global(:theme, quiet)
```

Native windows select dark or light initially and refresh the application theme
when system appearance changes. A system reduced-motion preference sets
`theme.motion.reduced?` and collapses animation durations to zero.
