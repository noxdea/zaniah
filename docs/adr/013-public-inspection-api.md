# ADR 013: Expose a stable inspection boundary

- Status: Accepted
- Date: 2026-09-24

## Context

External test drivers and DevTools currently read render state through internal instance variables or maintain duplicate tree walkers. Internal layout and platform state can change without notice, which makes downstream tooling fragile. One option is to expose each underlying object directly; another is to publish a read-only view of the latest frame.

## Decision

Publish `Zaniah::Inspection.snapshot(window)` as the external read boundary, backed by small, explicit read accessors on the existing objects. DevTools uses the same boundary. Snapshot values are frozen; the `Entry#element` reference remains live only until the next frame. During the 0.x series, a breaking change to this public API requires at least one minor release of deprecation before removal.

## Consequences

Inspection is constructed only when requested, avoiding per-frame traversal cost. The small accessors and compatibility period constrain internal refactors, but test drivers no longer depend on private instance variables. Native accessibility actions still require a current node and window.
