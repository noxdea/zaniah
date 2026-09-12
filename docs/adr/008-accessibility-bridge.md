# ADR 008: Separate the accessibility tree from OS bridges

- Status: Accepted
- Date: 2026-09-12
- Decision deadline: before M8 implementation

## Context

NSAccessibility, UI Automation, and AT-SPI expose different native contracts, but components need one testable semantic model.

## Decision

Build a backend-neutral accessibility tree first. Add Fiddle-based adapters for macOS, Windows, and Linux that publish tree differences without changing component APIs.

## Consequences

Semantics and diffs are tested headlessly. Native adapters publish layout-change
notifications through NSAccessibility, Windows accessibility events, and AT-SPI's
D-Bus event namespace while retaining the same backend-neutral tree for queries.
