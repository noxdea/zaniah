# ADR 004: Resolve interaction styles in elements before paint

- Status: Proposed
- Date: 2026-09-12
- Decision deadline: before M1 implementation

## Context

State-specific styles need stable layout inputs and same-frame hover feedback. Resolution could live in elements, the frame context, or a separate style object.

## Decision

Store variants in `StyleSet`, resolve flags from interaction state during prepaint, and let each element use the resolved style during paint. Keep `FrameContext` as a service carrier rather than a style owner.

## Consequences

Existing element builders remain compatible and paint stays deterministic. Elements must register hits when they only have state-specific styles.
