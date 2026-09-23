# Native backends

Zaniah provides native windows on macOS, Linux, and Windows. Headless and
terminal backends are available when a graphical window is unnecessary.

```ruby
window = Zaniah::Platform.open_window(
  backend: :mac,
  gpu: :metal,
  width: 800,
  height: 600,
  title: "Zaniah"
)

window.on_input { |event| p event }
window.draw { Zaniah::Div.new.bg("#123") }
window.run
```

| Backend | Renderer | Notes |
| --- | --- | --- |
| `:mac` | Metal (default) or OpenGL | Requires a graphical macOS session |
| `:linux` | Wayland/EGL or X11/GLX | Selected from `WAYLAND_DISPLAY` and `DISPLAY` |
| `:windows` | Win32/WGL | Requires 64-bit Ruby and Windows 10 APIs |
| `:headless` | Ruby software renderer | Deterministic rendering and PNG output |
| `:tui` | ANSI terminal | Text-grid rendering and terminal input |

On Linux, pass `display_server: :wayland` or `:x11` to require one display
server. On macOS, pass `gpu: :opengl` to use OpenGL instead of Metal.

For offscreen Vulkan rendering, use `GPU.create(backend: :vulkan, width:, height:)`.
It accepts the same `Scene` instance layout as Metal, OpenGL, and Software and
supports capture through `pixels` or `write_png`.

Native backends require Ruby's Fiddle library and the platform graphics
libraries. Fiddle is not a default gem on Ruby 4, so applications using native
windows must install it. Linux file dialogs and URL opening use `zenity` and
`xdg-open` when available.

Native windows support input and IME events, resizing, display scale, clipboard,
file drops, fullscreen, cursors, URL opening, file dialogs, appearance changes,
and PNG capture. Platform availability differs; see [the RBS declarations](../sig/native.rbs)
and [platform declarations](../sig/platform.rbs) for the exact API.

## Displays, file watching, and terminals

`Zaniah::Platform.displays` returns the available displays for a backend.
`Zaniah::Platform.watch(paths, latency:)` creates a native filesystem watcher;
call `poll(timeout:)` for events and `close` when finished. Overflow events mean
the application should rescan the watched paths.

macOS, Windows, and X11 windows support `move_to_display(display)`, using a
fresh `Display` returned by `Platform.displays` for the matching backend. It
moves the window frame to that display's top-left; it raises `Zaniah::Error` if
the display is no longer available. Headless and TUI windows reject placement.
Wayland has no arbitrary-position request: `move_to_display` raises, while
`fullscreen_on(display)` sends a best-effort output preference that the
compositor is free to ignore. Use `Platform.displays(backend: :linux,
display_server: :wayland)` to select the output.

On Windows, require `zaniah/platform/windows/terminal` to use
`Zaniah::Platform::Windows::Terminal`, which wraps ConPTY. It supports starting
a child process, nonblocking reads, writes, resizing, liveness checks, and
explicit cleanup. ConPTY requires Windows 10 version 1809 or later.

## Development checks

Run checks on the matching host and display server:

```sh
ruby examples/native_smoke.rb --check /tmp/zaniah.png
ruby examples/native_smoke.rb --gl --check /tmp/zaniah-gl.png
ruby examples/linux_smoke.rb
ruby examples/linux_smoke.rb --wayland
ruby examples/native_watch.rb
```

Linux XIM composition is exercised in CI with Xvfb and IBus/KKC. Native input,
IME on macOS and Windows, dialogs, and terminal integration also require manual
checks on the target operating system.
