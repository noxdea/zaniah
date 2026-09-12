# ADR 005: Extend the shared GPU instance layout once

- Status: Accepted
- Date: 2026-09-12
- Decision deadline: before M3 implementation

## Context

Metal, OpenGL, Vulkan, and Software consume the same 24-float instance payload. Gradients and transforms need more fields; changing the stride independently for each feature repeats risky backend work.

## Decision

Use this 40-float layout. Quad data uses every field; sprites reuse the edge
fields for source UVs. Triangle vertices reuse rect and radii fields.

| Floats | Quad | Sprite |
| --- | --- | --- |
| 0–3 | bounds | bounds |
| 4–7 | primary color | tint |
| 8–11 | secondary gradient color | unused |
| 12–15 | corner radii | unused |
| 16–19 | border color | unused |
| 20–23 | edge border widths | source UV |
| 24–27 | gradient kind, stop positions, angle | unused |
| 28–31 | gradient center, radius, primitive kind | primitive kind |
| 32–37 | affine transform (`a,b,c,d,tx,ty`) | affine transform |
| 38–39 | reserved shadow spread / inset or border flags | unused |

Opacity is multiplied into both fill and border alpha before packing. Linear
and radial gradients use exactly two stops; a future multi-stop implementation
may use a 1D texture without another stride change. Shadows are expanded into
ordinary quad instances, so the reserved shadow fields remain available.

Metal and OpenGL consume the layout directly, Software consumes the equivalent
40-float quad layout, and cached text sprite batches use the same stride.
`GPU::Vulkan` remains the repository's offscreen user-supplied SPIR-V probe; it
publishes the shared stride but does not yet present general `Scene` commands.

## Consequences

The coordinated change avoids multiple format migrations. Shader compilation,
Software golden tests, instance packing tests, and platform-native capture tests
are release gates on their available hosts.
