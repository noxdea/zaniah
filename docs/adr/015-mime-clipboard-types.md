# ADR 015: Use MIME names for clipboard representations

- Status: Proposed
- Date: 2026-09-24

## Context

Applications need to place text, HTML, images, and private formats on the
clipboard at the same time. Each operating system names these formats
differently. Exposing those native names would make application copy/paste
logic platform-specific; using a closed enum would exclude private formats.

## Decision

Use MIME strings as the public representation keys. Platform adapters map
common MIME names to native formats and preserve other names where the system
allows it. Items contain eagerly supplied, immutable data. The toolkit owns
transport and format negotiation, not conversion of application data.

## Consequences

Applications can offer multiple formats through one API without depending on
an OS adapter. Adapters must maintain the native mappings and account for
platform-specific limits. Lazy data providers may be added later if eager
copies become a measured problem.
