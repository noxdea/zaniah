# ADR 001: Use Metal on macOS and OpenGL on Linux and Windows

- Status: Accepted
- Date: 2026-09-10

## Context

Native windows need GPU rendering while keeping the gem free of compiled
extensions. Rendering must preserve scene order, clipping, and alpha blending,
and Ruby callbacks must not enter the VM from unsupported operating-system
threads.

The credible alternatives were one OpenGL backend for every desktop, native
Metal on macOS with OpenGL elsewhere, software rendering only, or a compiled
bridge that could safely receive display-link callbacks.

## Decision

macOS defaults to a `CAMetalLayer` and runtime-compiled Metal shaders, with
OpenGL as an explicit alternative. Linux uses OpenGL through GLX or EGL, and
Windows uses OpenGL through WGL. Headless rendering remains a separate software
backend.

Compatible adjacent scene commands are batched without reordering them. The Ruby
main thread polls native events and presents synchronized frames; native display
threads do not call Ruby through Fiddle.

## Consequences

Applications get native GPU windows without compiling repository code, and each
platform can use a supported presentation path. The project must maintain both
Metal and OpenGL renderers and test native behavior on each target platform.

Revisit this decision if a compiled bridge becomes acceptable, Ruby gains a safe
foreign-thread callback boundary, or maintaining parallel rendering APIs costs
more than the platform-specific benefits.
