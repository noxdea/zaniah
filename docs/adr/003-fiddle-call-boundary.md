# ADR 003: Batch frame work across the Fiddle boundary

- Status: Accepted
- Date: 2026-09-10

## Context

Crossing from Ruby into native functions has fixed conversion and dispatch cost.
A renderer that makes one native call per primitive scales that cost with scene
size. Objective-C calls may also reenter Ruby on the current thread, while
terminal reads may block for an unbounded period.

The credible alternatives were per-primitive native calls, cached wrappers with
batched frame data, or moving frame encoding into a compiled extension.

## Decision

Native function wrappers are cached by their full signature. Compatible adjacent
GPU commands are packed into instance buffers and submitted in batches rather
than one primitive at a time.

Objective-C dispatch keeps the GVL because callbacks may reenter Ruby. Blocking
ConPTY reads release it so other Ruby threads can continue.

## Consequences

Native-call overhead depends primarily on batch boundaries instead of primitive
count, while draw order and clipping remain explicit. Batching adds packing code,
and material, texture, or clip changes still split batches.

Revisit this decision if profiling shows boundary calls are no longer material,
batch construction dominates frame time, or a compiled renderer becomes an
accepted dependency.
