# ADR 009: Implement a bounded grid layout subset

- Status: Proposed
- Date: 2026-09-12
- Decision deadline: before M2 implementation

## Context

Full CSS Grid is too large for the toolkit's first grid implementation. Applications primarily need explicit tracks, spans, gaps, fractional space, and predictable automatic placement.

## Decision

Support explicit rows and columns, row-first auto placement, integer and range placement, `fr`, `minmax`, `auto`, and gaps. Defer named areas and `auto-fit`/`auto-fill`.

## Consequences

Common application layouts are covered with a tractable engine. Deferred CSS features require an explicit later extension.
