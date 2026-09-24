# ADR 022: Vertical writing and ruby clusters

- Status: Accepted
- Date: 2026-09-24

## Context

Japanese documents need top-to-bottom lines, columns that progress right to
left, and annotations adjacent to their parent text. Rotating an entire
horizontal line would give incorrect caret, selection, wrapping, and ruby
geometry. Inserting ruby readings into the text buffer would also corrupt
logical UTF-8 offsets and copied text.

## Decision

`Paragraph`, `Text`, and `UI::RichText` accept `writing_mode: :vertical_rl`.
The inline limit is measured top to bottom, and layout converts inline and
cross axes to physical coordinates for painting and interaction. The built-in
shaper uses OpenType `vmtx` advances and GSUB `vert`/`vrt2` when a font supplies
them. Mixed orientation keeps CJK upright and rotates ordinary Latin glyphs;
`:upright` suppresses that rotation. A RichText run can request
`combine_upright: true` for a compact horizontal run inside a vertical line.

Ruby is a style on a parent run, not buffer content. The run is an unbreakable
editing cluster. Its annotation is centered above the parent in horizontal
text or to its right in vertical text. Both parent and annotation contribute
to inline/cross box size, but only the parent contributes to copied text.
Accessibility and TUI readings include the annotation in parentheses.

## Consequences

Caret, hit testing, selection, and IME rectangles share the axis conversion
used by painting; stored offsets remain logical UTF-8 byte offsets. Ruby and
combine-upright cannot be combined on one run. The implementation does not
claim full CSS Writing Modes or OpenType vertical typography: `VORG`, vertical
GPOS kerning/mark positioning, and font-specific vertical baseline correction
remain unsupported. Fonts without vertical tables use horizontal advances.
