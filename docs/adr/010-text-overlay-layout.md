# ADR 010: Model text overlays as layout gaps

- Status: Accepted
- Date: 2026-09-15
- Decision deadline: before text overlay implementation

## Context

Inline hints and block annotations must affect wrapping and pointer mapping without
becoming editable text. Absolutely painting them over an ordinary paragraph would
leave wrapping, carets, and selection unaware of their size.

## Decision

Represent inline overlays as measured gaps at UTF-8 grapheme boundaries and block
overlays as measured rows around logical source lines. Cache the wrapped paragraph
for each explicit source line so changing one inline overlay only reshapes that row.
Keep overlay elements as ordinary positioned children for painting and input.

## Consequences

Text offsets remain unchanged, overlay children stay clickable, and coordinate
conversion accounts for every gap. Layout changes after an overlay row still shift
later vertical positions, but those rows reuse their shaped and wrapped paragraphs.
