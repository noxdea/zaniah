# ADR 014: Route UI commands through focused handlers before app actions

- Status: Proposed
- Date: 2026-09-24

## Context

Keyboard actions currently reach only focused handlers. Menus, palettes, context
menus, and accessibility actions need the same behavior, including a way to ask
whether an item is enabled without executing it. Routing each source separately
would make focus precedence and disabled states diverge.

Native menu accelerators introduce a separate risk: macOS can process a
`keyEquivalent` in addition to the framework keymap. Keeping both active could
execute one command twice.

## Decision

Use `Dispatcher#perform` for all command sources. Focused handlers take precedence
from leaf to root, followed by `App#actions`. A focused handle can provide a
side-effect-free `validate` callback: `false` blocks the command, `true` enables
it, and `nil` defers to the next handle. `available?` asks validators and the app
registry without invoking action handlers. Legacy focused handlers without a
validator remain executable but cannot advertise availability by themselves.

An unvalidated legacy focus handler still executes before a disabled app
command, even though `available?` can only report the app command as disabled.
Such focused actions need `validate` to advertise their own availability.

Keyboard focus movement remains a dispatcher concern. Native menu shortcuts
must be routed through the Zaniah keymap exactly once; platform adapters must
verify that native `keyEquivalent` processing does not also invoke the command.

## Consequences

Menus and palettes can share dispatch and validation with keyboard input, and
app-wide commands remain available when no focus handler consumes them. Focused
actions intended for menus must provide `validate`; an opaque handler alone
cannot safely report support without being run. Native shortcut behavior needs
platform verification before this ADR can be accepted.
