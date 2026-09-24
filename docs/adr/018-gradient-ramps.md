# ADR 018: Use bounded ramps for multistop gradients

- Status: Accepted
- Date: 2026-09-24

## Context

The shared instance format carries only two inline stop colors. Extending its
stride would affect every renderer and text/sprite packing.

## Decision

Two-stop linear and radial gradients retain their inline color path. Two-stop
conic gradients use kind `3` and the same interpolation path. Three or more
stops use kinds `4` (linear), `5` (radial), or `6` (conic), and one row of a
256-by-256 RGBA8 atlas baked from the ordered stops. Field 8 stores the row
index; all renderers sample that row at the calculated gradient position. A
`Scene` caches rows by immutable `Gradient` value in an LRU capped at 256
entries. Rows used in the current frame cannot be evicted; if a frame exceeds
256 distinct ramps, it uses reusable overflow atlases for the remainder of
that frame. Normal quads continue to use packed-byte fast paths; only ramp
quads need texture-aware batching.

## Consequences

No instance layout migration is required. Sampling precision is limited to
256 positions. Adjacent ramps on the shared atlas batch together, while
overflows can add batches. SVG gradient fills use the same ordered-stop
interpolation semantics and fall back to a raster snapshot in vector recording
because a `Vector::Path` currently stores solid fills only.
