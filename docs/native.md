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

## Clipboard representations

`Clipboard::Item` holds eager MIME-keyed data. `text/*` values are UTF-8 text;
other values are bytes. The window's `clipboard` and `clipboard=` methods remain
shortcuts for `text/plain`.

```ruby
item = Zaniah::Clipboard::Item.new(
  "text/plain" => "a\tb",
  "text/html" => "<b>a</b>",
  "image/png" => png_bytes
)
window.write_clipboard([item])
window.clipboard_types                   # available MIME names, without reading data
content = window.read_clipboard(types: ["text/html", "text/plain"])
content.types                            # formats found, in requested order
content.fetch("text/html")
```

Headless keeps representations in per-window memory. TUI also keeps every
representation in memory and sends only `text/plain` writes to the terminal
with OSC 52; it cannot read the terminal's clipboard. Native macOS, Windows,
X11, and Wayland exchange `text/plain`, `text/html`, and `image/png` with other
applications. macOS also preserves arbitrary MIME types under reversible
`com.noxdea.zaniah.mime.<hex>` pasteboard identifiers; Windows, X11, and
Wayland use their native format mechanisms. Native clipboard exchange still
depends on a running desktop session and should be checked on each target OS.

## Window state and decorations

`window.frame` uses logical screen coordinates; `window.state.to_h` can be saved
by the application and passed back to `window.restore_state`. Missing displays
and offscreen frames are corrected toward the primary display. `maximize`,
`minimize`, `restore`, `fullscreen?`, `always_on_top=`, and `on_state_change`
operate on the native window where supported. `decorations: :native` is the
default; `:hidden_titlebar` and `:none` enable a custom titlebar built from
`window_drag_region` and `window_control` elements. `min_size:`, `resizable:`,
and macOS-only `traffic_lights:` are creation options.

X11 window managers must support EWMH for state and drag requests. On X11,
`:hidden_titlebar` has the same no-decoration effect as `:none` through Motif
hints. Wayland does not expose a window position: its frame origin is `nil`
and setting a position raises. Wayland also cannot request always-on-top or
programmatically restore a minimized window; those operations raise rather
than claim success. Client-side decorations on Wayland depend on the compositor
and its decoration protocol. Verify native placement and drag behavior on each
target desktop before relying on it.

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
ruby examples/native_menu.rb              # macOS only
```

Linux XIM composition is exercised in CI with Xvfb and IBus/KKC. Native input,
IME on macOS and Windows, dialogs, and terminal integration also require manual
checks on the target operating system.
