# ADR 020: Lightweight code editor provider boundaries

- Status: Accepted
- Date: 2026-09-24

## Context

The original CodeEditor passed an entire document through one Text element and
constructed a second Text element containing every line number. Both scale with
the whole file, and the two elements disagree about row heights when code
wraps. Applications may already have a rope buffer or incremental syntax
highlighter; bundling either implementation here would duplicate their work.

## Decision

CodeEditor accepts a line-addressable buffer with `line_count`, `line(index)`,
`line_start(index)`, `line_of(offset)`, `replace(range, text)`, `undo`, and
`redo`. The default adapter wraps TextBuffer and indexes UTF-8 byte starts.
`to_s` is optional for external providers. A highlighter supplies
`tokens(line_index, text)` as byte ranges and scopes, and receives
`edited(range, new_text)` after edits. Token scopes resolve through
`theme.syntax`; the editor owns no parser or language grammar.

The dedicated Surface uses List::HeightIndex to shape and paint only visible
logical lines. A wrapped logical line owns all its display rows, so its line
number is painted once at the first display row. The Surface owns one caret,
one selection, IME candidate placement, standard text actions, and Tab
indentation. The existing positional constructor remains accepted.

## Consequences

Buffer adapters must keep byte offsets stable and return UTF-8 lines. A
highlighter can cache tokens incrementally, but may only paint within the
current viewport. Multi-cursor editing, folding, LSP, and a minimap remain
application concerns. Unknown row heights use an estimate until those rows
are visited, so scrollbar position can refine as wrapped lines are measured.
