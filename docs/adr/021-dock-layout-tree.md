# ADR 021: Represent dock layouts as a validated tree

- Status: Accepted
- Date: 2026-09-24

## Context

An application needs to save tabbed, split workspaces and restore them across
sessions. Dragging a tab changes both its group and potentially the split tree.
A fixed five-region dock cannot represent nested splits or stable panel identity.

## Decision

`UI::DockLayout` stores tab groups and binary splits with stable string IDs.
`to_h` and `from_h` provide a plain-data round trip; parsing rejects duplicate
IDs, empty groups, invalid active tabs, invalid orientations, and out-of-range
ratios. `UI::DockWorkspace` derives visible panes from this model and reuses
`UI::SplitPane` for dividers. Layout changes produce a new validated model.
The application owns persistence and handles `on_detach` notifications; the
component does not create windows.

## Alternatives considered

- A flat list of panels plus coordinates would make nested resizing and
  restoration ambiguous.
- Extending `DockPanel` would change its simple five-region contract.
- Making detach automatically create windows would assume application policy.

## Consequences

Persisted layouts can be validated independently of rendering. Empty groups
are pruned after a move. Applications can choose their own storage format and
window ownership; they must keep panel IDs stable across releases.
