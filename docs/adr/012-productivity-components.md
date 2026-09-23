# ADR 012: Keep productivity components separate from existing controls

- Status: Accepted
- Date: 2026-09-23

## Context

The spreadsheet and presentation applications need sparse two-axis grids and
inline rich-text editing. `UI::Table` models records by column definitions;
`List::HeightIndex` indexes one axis; and `UI::TextInputs` edits plain text.

## Decision

- Use a dedicated virtualized `UI::Grid`; `UI::Table` is not a substitute for
  million-row sparse cell coordinates, range selection, or frozen panes.
- Reuse `List::HeightIndex` independently for each grid axis rather than
  generalizing it into a second indexing abstraction.
- Keep `UI::TextInputs` unchanged and implement inline rich text in a separate
  surface so existing plain-text editing behavior remains stable.

## Consequences

The productivity features stay additive and preserve existing table and text
input APIs. The grid shares the tested prefix-index implementation while
maintaining separate row and column state.
