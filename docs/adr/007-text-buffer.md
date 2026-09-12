# ADR 007: Start with a String-backed text buffer

- Status: Proposed
- Date: 2026-09-12
- Decision deadline: before M5 implementation

## Context

Text editing needs Unicode-safe changes and undo. A piece table scales better for very large documents, while a Ruby `String` is substantially simpler for the intended settings and editor examples.

## Decision

Use a mutable UTF-8 `String` with byte offsets and grapheme-aware navigation. Revisit a piece table only after representative documents show a measurable problem.

## Consequences

The first implementation is small and easy to verify. Large edits are linear in buffer size.
