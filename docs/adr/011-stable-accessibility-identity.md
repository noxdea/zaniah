# ADR 011: Match accessibility descendants by stable identity

- Status: Accepted
- Date: 2026-09-15
- Decision deadline: before screen-reader virtualization support

## Context

Position-only semantic paths change when a virtual viewport scrolls or siblings
are reordered. Native bridges then expose a previously known item as a different
object, and coordinate-generated actions can target the wrong virtual row.

## Decision

Let semantic nodes carry an optional immutable ID that is unique among siblings.
Match identified siblings by ID when diffing and retain native runtime IDs across
tree publications. Keep offscreen rows absent. Route actions on synthesized nodes
back to their owning component, and derive native structure, property, layout,
focus, and live-region events from the shared semantic diff.

## Consequences

Virtual tree rows, reordered panes, and live status nodes regain their native
identity when their semantic node moves. Components remain responsible for stable
domain IDs and expose no platform objects. Unidentified nodes retain positional
matching and coordinate action fallback for compatibility.
