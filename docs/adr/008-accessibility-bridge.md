# ADR 008: Separate the accessibility tree from OS bridges

- Status: Proposed
- Date: 2026-09-12
- Decision deadline: before M8 implementation

## Context

NSAccessibility, UI Automation, and AT-SPI expose different native contracts, but components need one testable semantic model.

## Decision

Build a backend-neutral accessibility tree first. Add Fiddle-based adapters for macOS, Windows, and Linux that publish tree differences without changing component APIs.

## Consequences

Semantics can be tested headlessly and native adapters can ship independently. Each adapter still requires platform-specific integration tests.
