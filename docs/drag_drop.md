# Drag-and-drop reordering

`DragDrop::Reorder` coordinates pointer and keyboard reordering without owning the
application's collection. It identifies items by stable IDs and reports a
`DragDrop::Target` whose position is `before`, `after`, or `inside`.

```ruby
reorder = Zaniah::DragDrop::Reorder.new(
  threshold: 4,
  locate: ->(point, source_id) { target_at(point, excluding: source_id) },
  keyboard: ->(id, direction) { adjacent_target(id, direction) },
  label: ->(id) { item_label(id) }
).on_drop do |event|
  move_item(event.source_id, event.target.id, event.target.position)
end

row
  .on_mouse_down { |event, _| reorder.press(row_id, event.position) }
  .on_drag { |event, _| reorder.move(event.position) }
  .on_mouse_up { |event, _| reorder.release(event.position) }
  .focusable(context: {reorderable: true}) { |action| reorder.action(row_id, action) }
```

The pointer locator is called only after the drag threshold is crossed. Virtual
lists can derive a row with `List::HeightIndex#index_at`; uniform lists can use
division by row height. Tree views can resolve a visible segment and return an
`inside` target only for containers. No API requires enumerating or rendering the
whole collection. Return `nil` for collection-specific no-ops, such as placing an
item after its current predecessor.

Listen with `on_event` for `press`, `start`, `enter`, `over`, `leave`, `drop`, and
`cancel`. Call `remove(id)` when application data removes a source or current
target, and call `cancel` when an enclosing interaction ends. Callback failures
reset transient drag state before being re-raised. Callbacks may update the
application collection, but must not re-enter their `Reorder` controller; an
attempt raises `Zaniah::Error` and cancels the active operation.

For keyboard access, mark the focused element with `reorderable: true`. Alt+Up
and Alt+Down dispatch `reorder_before` and `reorder_after`; Escape dispatches
`cancel_reorder`. `accessibility_node` exposes the last result as a live `status`
node. Include that node in the containing component's accessibility children, or
forward `on_announce` to its existing live region. Native file drops are separate
and are not handled by this primitive. The controller belongs to its UI owner:
call it on that owner's event thread and `cancel` before the owner is discarded.
