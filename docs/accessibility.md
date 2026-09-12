# Accessibility

Every window maintains a backend-neutral `Accessibility::Tree` beside its render
tree. Components expose role, label, value, bounds, states, children, and actions
through `Accessibility::Node`. The window publishes a notification only when the
semantic tree changes.

```ruby
window.accessibility_tree.each do |node, path|
  puts [path, node.role, node.label].inspect
end
```

`window.accessibility_revision` increments after each semantic change, and
`window.accessibility_tree.changes` contains `added`, `removed`, or `updated`
records. This makes accessibility assertions deterministic on the headless
backend without mocking an operating system API.

## Component semantics

Interactive components publish their current state and supported actions. For
example, checkboxes expose `checked`, mixed checkboxes expose `mixed`, disabled
controls omit mutating actions, modal dialogs expose `modal`, and live Toast
messages use the `status` role. `FormField` marks invalid controls and associates
the error node through its `describedby` state.

Custom components implement the same method:

```ruby
def accessibility_node(_cx)
  Zaniah::Accessibility.node(
    role: :button,
    label: "Refresh",
    states: {busy: @loading},
    actions: @loading ? [] : [:press]
  )
end
```

Decorative content should return `nil`. Container elements without an explicit
node retain semantic descendants in a generated `group` node.

## Native bridges

- macOS maps the application root to an NSAccessibility role and posts an
  `AXLayoutChanged` notification.
- Windows emits `EVENT_OBJECT_REORDER` for the client object so UI Automation
  and legacy accessibility clients refresh the window provider.
- Linux emits the corresponding AT-SPI object event on the session D-Bus.

The semantic tree remains the authoritative source on every backend. See
[ADR-008](adr/008-accessibility-bridge.md) for the boundary between components
and native adapters.
