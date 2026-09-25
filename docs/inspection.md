# Frame inspection

`Zaniah::Inspection` gives test drivers and DevTools a public, read-only view of the latest rendered frame. It works with headless and native windows.

```ruby
window.render(root)
snapshot = Zaniah::Inspection.snapshot(window)
save = snapshot.find(test_id: "save")
buttons = snapshot.where(type: Zaniah::UI::Button)
frontmost = snapshot.at(Zaniah::Point.new(120, 40))
node, path = snapshot.accessibility.query(role: :button, label: /save/i).first
Zaniah::Inspection.perform(window, node, :press)
```

`snapshot.root` and its children expose type, key, test ID, window-space bounds, resolved style, tooltip, context menu, handlers, and focus state. `snapshot.overlays` exposes tooltip, popup, and menu state; `snapshot.text_runs` contains rendered text; `snapshot.frame` contains a monotonically increasing frame number and timing statistics. `snapshot.find` returns the first match, `where` returns all matches, and `at` uses the frontmost registered hit region. A newly opened window has no root until its first render.

The snapshot containers and copied collections are frozen. `entry.element` is deliberately a live element reference: use it only in the same frame, because the next render may replace it. Accessibility nodes are copied for inspection; pass one to `Inspection.perform` to invoke an action on its current source node. Actions require a node from the current frame. To wait for a settled UI, call `Zaniah::Inspection.idle?(app)` after draining queued work and rendering dirty windows.

The public API is declared in [`sig/inspection.rbs`](../sig/inspection.rbs).
Breaking changes receive at least one minor version of deprecation during 0.x,
as recorded in [ADR 013](adr/013-public-inspection-api.md).
