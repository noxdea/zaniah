# ADR 006: Components participate by duck typing

- Status: Accepted
- Date: 2026-09-12
- Decision deadline: before M6 implementation

## Context

Components can inherit `Element` or wrap an element tree while implementing the existing render protocol. Inheritance exposes low-level mutable state that components do not need.

## Decision

Components implement `request_layout`, `layout_node`, `prepaint`, and `paint`, delegating those calls to a built root element.

## Consequences

The UI layer stays optional and thin. Protocol changes must be reflected in both elements and components.
