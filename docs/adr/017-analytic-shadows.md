# ADR 017: Draw each shadow as one analytic instance

- Status: Accepted
- Date: 2026-09-24

## Context

The previous shadow approximation layered eight rounded quads. It produced
visible bands and made a scene with 100 shadows submit 800 instances.

## Decision

Keep the 40-float instance layout from ADR 005. Primitive kind `4` in field 31
is a shadow; field 30 is blur sigma, field 38 is spread, and field 39 is the
inset flag. Bounds 0–3 are expanded by `spread + 3 * blur + 1` for outer
shadows. Inset shadows retain the original bounds. Corner radii occupy 12–15.

Software and all three GPU fragment shaders evaluate the signed distance to
the original rounded rectangle. A Gaussian edge is approximated by
`0.5 - 0.5 * erf((distance - spread) / (sqrt(2) * blur))`, using the same bounded
exponential approximation of `erf` in every backend. Zero blur uses direct
coverage. Inset shadows multiply interior coverage by the inverted transition.
The existing clipping, transforms, and alpha blending remain unchanged.

## Consequences

Shadow appearance intentionally changes; the golden images and changelog must
record this. `bench/shadow.rb` compares 100 shadows against the old eight-quad
approximation and requires the analytic Software path to be faster. GPU native
capture tests remain platform-dependent; `script/compile_shaders` regenerates
the bundled Vulkan SPIR-V from the checked-in GLSL.
