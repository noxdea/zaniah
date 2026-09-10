# ADR 002: Describe Objective-C aggregate values with system libffi

- Status: Accepted
- Date: 2026-09-10

## Context

AppKit and related frameworks pass values such as `NSRect` and `NSRange` by
value. Fiddle function signatures expose scalar types but cannot describe these
aggregate arguments and return values accurately. Their calling conventions also
differ between arm64 and x86_64.

The credible alternatives were treating aggregates as pointers, writing a C
extension or generated trampoline for each signature, or describing the native
ABI through the system libffi library already used by Fiddle.

## Decision

`FFI::Struct::Signature` describes aggregate layouts to system libffi and invokes
them with `ffi_call`. The same mechanism creates closures with aggregate
arguments and returns. Objective-C dispatch signatures are cached; arm64 uses
its native aggregate ABI, while x86_64 uses `objc_msgSend_stret` where required.

Native pointers and Ruby closures have explicit owners, and callbacks are retained
for as long as native code may invoke them.

## Consequences

Aggregate calls follow each platform ABI without a compiler or C extension. The
trade-off is a small internal FFI layer that must model architecture-specific
dispatch and object lifetimes correctly.

Revisit this decision if Fiddle gains complete aggregate signatures or if the
project adopts a compiled native boundary for other reasons.
