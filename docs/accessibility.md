# Accessibility

Every window maintains a backend-neutral `Accessibility::Tree` beside its render
tree. Components expose a stable ID, role, label, value, bounds, states, children,
and actions through `Accessibility::Node`. The window publishes notifications only
when the semantic tree changes.

```ruby
window.accessibility_tree.each do |node, path|
  puts [path, node.role, node.label].inspect
end
```

`window.accessibility_revision` increments after each semantic change.
`window.accessibility_tree.changes` contains `added`, `removed`, `updated`, or
`moved` records; stable IDs let a reorder remain a move instead of two unrelated
updates. IDs must be immutable and unique among siblings. The accompanying
`events` reduce those changes to deterministic `structure`, `property`, `layout`,
`focus`, and `announcement` events. This makes accessibility assertions
deterministic on the headless backend without mocking an operating system API.

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
    id: :refresh,
    label: "Refresh",
    states: {busy: @loading},
    actions: @loading ? [] : [:press]
  )
end
```

If a component synthesizes semantic descendants, it can route their actions
without coordinate hit testing:

```ruby
def accessibility_action(node, action)
  refresh(node.id) if action == :press
end
```

`TreeView` uses item IDs for its viewport-only descendants and reports the
selected descendant as focused while the tree owns keyboard focus. Its select,
expand, and collapse actions call the tree model directly. `PaneGrid` gives panes
and dividers stable IDs and routes divider increment, decrement, minimum, and
maximum actions through the same resizing path as the keyboard. A
`DragDrop::Reorder` exposes keyboard reorder actions and a stable, atomic polite
live region for move and cancellation results. Offscreen virtual rows remain
unmaterialized; when they re-enter the viewport, their IDs reconnect them to the
same native identity.

Decorative content should return `nil`. Container elements without an explicit
node retain semantic descendants in a generated `group` node.

## Native bridges

- macOS publishes an `NSAccessibilityElement` hierarchy with identifiers, roles,
  labels, values, state, bounds, and children, then posts layout, value, focus,
  and announcement notifications from semantic events.
- Windows answers `WM_GETOBJECT` with `IRawElementProviderSimple`, fragment,
  fragment-root, and Invoke providers. UI Automation clients can navigate and
  query stable Automation IDs and receive structure, property, layout, focus,
  and live-region events rather than relying on refresh events alone.
- Linux registers `Accessible`, `Component`, `Action`, and `Application`
  objects on the AT-SPI D-Bus, embeds the application root in the registry,
  retains stable `AccessibleId` values and object paths, and emits matching
  object, state, and announcement events. Actions route back through the normal
  input dispatcher or a component's direct semantic action on every platform.

The Linux provider is exercised in CI inside a private D-Bus session. Native
macOS and Windows objects retain the same `Accessibility::NativeTree` path and
bounds model used by the headless assertions.

The semantic tree remains the authoritative source on every backend. See
[ADR-008](adr/008-accessibility-bridge.md) for the boundary between components
and native adapters.
