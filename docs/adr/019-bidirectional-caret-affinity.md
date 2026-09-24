# ADR 019: Bidirectional caret affinity

- Status: Accepted
- Date: 2026-09-24

## Context

UTF-8 byte offsets identify logical text positions, but a boundary between
left-to-right and right-to-left runs can appear at two visual positions. A
single `offset → x` mapping therefore loses information needed for pointer
selection and arrow-key movement. Keeping logical movement only would avoid
this ambiguity but would make arrow keys travel opposite to their visual
direction inside right-to-left text. Storing display-order text instead would
break editing, copying, and external byte-offset contracts.

## Decision

Keep text and selection offsets in logical UTF-8 byte order. A rendered line
may associate an offset with upstream and downstream visual caret positions.
Pointer hit testing returns both offset and affinity; existing offset-only
methods remain as compatibility shortcuts. Arrow keys move through visual
carets by default, while `caret_movement: :logical` preserves storage-order
movement for applications such as code editors.

Selection is a logical byte range rendered as a set of visual rectangles.
The Unicode Bidirectional Algorithm resolves the paragraph before line-local
reordering; neither glyph painting nor hit testing changes stored text order.

## Consequences

The editing path must retain affinity separately from the selection offset,
and callers that want an exact caret position must use the affinity-aware
methods. Existing LTR offset and caret APIs keep their values. This decision
can be revisited if a platform-specific native text editor is adopted as the
storage and interaction model instead of the toolkit's own text buffer.
