# ADR 016: Record semantic drawing alongside the GPU scene

- Status: Proposed
- Date: 2026-09-24

## Context

The GPU scene contains packed quads and atlas sprites. Paths have already been
rasterized and text has lost its font, glyph IDs, and source clusters by the
time a renderer consumes those commands. Exporters need this information to
produce searchable text and scalable artwork. Reconstructing it from packed
GPU instances is impossible; maintaining a second application-specific layout
for export makes screen and export drift.

Two viable boundaries were considered: make the GPU scene itself semantic, or
keep its fast packed representation and optionally observe the drawing calls.

## Decision

Keep the GPU scene unchanged and attach an optional vector sink to `Scene`.
Emit semantic commands before paths and text are flattened. When a source has
no supported vector form, preserve its pixels as a raster command instead.
The sink is absent by default, so normal frames do not allocate vector data.
Page assembly and document formats remain outside Zaniah.

## Consequences

Exporters can reuse the same element tree and retain font and outline data
without adding a dependency on a PDF library. The optional path incurs a
nil check when unused and stores additional frame data when enabled. Raster
fallbacks keep output complete but cannot scale as cleanly as true vectors.
This choice should be revisited if packed GPU commands become a lossless
semantic representation or a common display list can serve both consumers.
