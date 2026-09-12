# ADR 005: Extend the shared GPU instance layout once

- Status: Proposed
- Date: 2026-09-12
- Decision deadline: before M3 implementation

## Context

Metal, OpenGL, Vulkan, and Software consume the same 24-float instance payload. Gradients and transforms need more fields; changing the stride independently for each feature repeats risky backend work.

## Decision

Design one 40-float layout for gradients, affine transforms, opacity, shadows, edge widths, and corner radii, then update every backend together. Opacity may ship first by multiplying color alpha without changing the stride.

## Consequences

The coordinated change is larger but avoids multiple format migrations. All backend golden tests become a release gate.
