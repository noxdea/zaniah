# frozen_string_literal: true

require "fiddle/import"
require "uri"
require "open3"
require_relative "../../ffi/library"
require_relative "../../gpu/open_gl"
require_relative "appearance_aware"
require_relative "displays"

module Zaniah
  module Platform
    module Linux
      module Types
        extend Fiddle::Importer
        Visual = struct ["void *visual", "unsigned long visualid", "int screen", "int depth", "int c_class", "unsigned long red_mask", "unsigned long green_mask", "unsigned long blue_mask", "int colormap_size", "int bits_per_rgb"]
        Attributes = struct ["unsigned long background_pixmap", "unsigned long background_pixel", "unsigned long border_pixmap", "unsigned long border_pixel", "int bit_gravity", "int win_gravity", "int backing_store", "unsigned long backing_planes", "unsigned long backing_pixel", "int save_under", "long event_mask", "long do_not_propagate_mask", "int override_redirect", "unsigned long colormap", "unsigned long cursor"]
        SizeHints = struct ["long flags", "int x", "int y", "int width", "int height", "int min_width", "int min_height", "int max_width", "int max_height", "int width_inc", "int height_inc", "int min_aspect_x", "int min_aspect_y", "int max_aspect_x", "int max_aspect_y", "int base_width", "int base_height", "int win_gravity"]
      end

      # X11 works on Xorg and through XWayland on Wayland sessions.
      class Window < Headless::Window
        include AppearanceAware
        def displays = Linux.displays(display_server: :x11)
        I, L, P, V = Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOID
        attr_reader :handle, :display
        def self.new(display_server: :auto, **options)
          raise ArgumentError, "unknown Linux display server" unless [:auto, :x11, :wayland].include?(display_server)
          if display_server == :wayland || (display_server == :auto && ENV["WAYLAND_DISPLAY"])
            begin
              require_relative "wayland_window"
              return WaylandWindow.new(**options)
            rescue LoadError, Error => error
              raise if display_server == :wayland || !ENV["DISPLAY"]
              warn "Zaniah UI: Wayland unavailable (#{error.message}); trying X11"
            end
          end
          super(**options)
        end
        def initialize(gpu: :opengl, **options)
          super(**options)
          raise Error, "traffic_lights is only supported on macOS" if traffic_lights
          @x = FFI::Library.new("libX11.so.6")
          @gl = FFI::Library.new("libGL.so.1")
          @display = x(:XOpenDisplay, [P], P, 0)
          raise Error, "cannot open X display; set DISPLAY (Wayland requires XWayland)" if @display.null?
          @screen = x(:XDefaultScreen, [P], I, @display)
          @root = x(:XRootWindow, [P, I], L, @display, @screen)
          attributes = [0x8012, 1, 0x8010, 1, 0x8011, 1, 8, 8, 9, 8, 10, 8, 11, 8, 5, 1, 0].pack("i*")
          count = [0].pack("i")
          configs = @gl.fn(:glXChooseFBConfig, [P, I, P, P], P).call(@display, @screen, attributes, count)
          raise Error, "no GLX framebuffer configuration" if configs.null? || count.unpack1("i").zero?
          @config = Fiddle::Pointer.new(configs)[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
          visual_ptr = @gl.fn(:glXGetVisualFromFBConfig, [P, P], P).call(@display, @config)
          visual = Types::Visual.new(visual_ptr)
          @colormap = x(:XCreateColormap, [P, L, P, I], L, @display, @root, visual.visual, 0)
          attrs = Types::Attributes.malloc(Fiddle::RUBY_FREE)
          attrs.to_ptr[0, Types::Attributes.size] = "\0" * Types::Attributes.size
          attrs.colormap = @colormap
          attrs.event_mask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 6) | (1 << 15) | (1 << 17) | (1 << 21) | (1 << 22)
          @handle = x(:XCreateWindow, [P, L, I, I, I, I, I, I, I, P, L, P], L, @display, @root, 0, 0, content_size.width.to_i, content_size.height.to_i, 0, visual.depth, 1, visual.visual, (1 << 11) | (1 << 13), attrs)
          x(:XFree, [P], I, visual_ptr)
          x(:XFree, [P], I, configs)
          raise Error, "XCreateWindow failed" if @handle.zero?
          @atoms = {}
          configure_decorations
          protocol = [atom("WM_DELETE_WINDOW")].pack("L!")
          x(:XSetWMProtocols, [P, L, P, I], I, @display, @handle, protocol, 1)
          property(@handle, atom("XdndAware"), 4, [5].pack("L!"), format: 32)
          self.title = @title
          dpi = @x.fn(:XResourceManagerString, [P], P).call(@display)
          @scale_factor = dpi.null? ? 1.0 : (dpi.to_s[/Xft\.dpi:\s*(\d+(?:\.\d+)?)/, 1]&.to_f || 96) / 96.0
          @scale_factor = @scale_factor.clamp(1.0, 4.0)
          @content_size = Size.new(content_size.width / @scale_factor, content_size.height / @scale_factor)
          configure_size_hints
          @device.release
          @device = create_device(gpu)
          x(:XMapWindow, [P, L], I, @display, @handle)
          x(:XFlush, [P], I, @display)
          setup_ime
          setup_display_events
        end
        def x(name, types, result, *values) = @x.fn(name, types, result).call(*values)
        def atom(name) = @atoms[name] ||= x(:XInternAtom, [P, P, I], L, @display, name, 0)
        def create_device(backend)
          raise ArgumentError, "X11 supports :opengl" unless [:opengl, :gl].include?(backend)
          resolver = ->(name) { @gl.fn(:glXGetProcAddressARB, [P], P).call(name) }
          address = resolver.call("glXCreateContextAttribsARB")
          raise Error, "GLX_ARB_create_context unavailable" if address.null?
          create = Fiddle::Function.new(address, [P, P, P, I, P], P)
          attributes = [0x2091, 3, 0x2092, 3, 0x9126, 1, 0].pack("i*")
          @context = create.call(@display, @config, 0, 1, attributes)
          raise Error, "OpenGL 3.3 context unavailable" if @context.null?
          make_current
          extension = @gl.fn(:glXQueryExtensionsString, [P, I], P).call(@display, @screen).to_s
          if extension.split.include?("GLX_EXT_swap_control")
            Fiddle::Function.new(resolver.call("glXSwapIntervalEXT"), [P, L, I], V).call(@display, @handle, 1)
          end
          GPU::OpenGL.new(self, library: @gl, resolver: resolver)
        end
        def make_current
          ok = @gl.fn(:glXMakeCurrent, [P, L, P], I).call(@display, @handle, @context)
          raise Error, "glXMakeCurrent failed" if ok.zero?
        end
        def swap_buffers = @gl.fn(:glXSwapBuffers, [P, L], V).call(@display, @handle)
        def title=(title)
          super
          return unless @handle
          x(:XStoreName, [P, L, P], I, @display, @handle, title)
          property(@handle, atom("_NET_WM_NAME"), atom("UTF8_STRING"), title.encode("UTF-8"))
        end
        def configure_decorations
          return if decorations == :native
          # Motif hints are understood by the X11 window managers that implement CSD.
          property(@handle, atom("_MOTIF_WM_HINTS"), atom("_MOTIF_WM_HINTS"), [2, 0, 0, 0, 0].pack("L!5"), format: 32)
        end
        def configure_size_hints
          return if resizable && !min_size
          hints = Types::SizeHints.malloc(Fiddle::RUBY_FREE)
          hints.to_ptr[0, Types::SizeHints.size] = "\0" * Types::SizeHints.size
          size = resizable ? min_size : content_size
          hints.flags = resizable ? 1 << 4 : (1 << 4) | (1 << 5)
          hints.min_width = (size.width * @scale_factor).ceil
          hints.min_height = (size.height * @scale_factor).ceil
          hints.max_width = hints.min_width unless resizable
          hints.max_height = hints.min_height unless resizable
          x(:XSetWMNormalHints, [P, L, P], V, @display, @handle, hints)
        end
        def frame
          return super if !@handle || closed?
          root, x_pos, y_pos, width, height, border, depth = [0].pack("L!"), [0].pack("i"), [0].pack("i"), [0].pack("I"), [0].pack("I"), [0].pack("I"), [0].pack("I")
          ok = x(:XGetGeometry, [P, L, P, P, P, P, P, P, P], I, @display, @handle, root, x_pos, y_pos, width, height, border, depth)
          raise Error, "XGetGeometry failed" if ok.zero?
          left, top, child = [0].pack("i"), [0].pack("i"), [0].pack("L!")
          ok = x(:XTranslateCoordinates, [P, L, L, I, I, P, P, P], I, @display, @handle, @root, 0, 0, left, top, child)
          raise Error, "XTranslateCoordinates failed" if ok.zero?
          Bounds.new(left.unpack1("i") / @scale_factor, top.unpack1("i") / @scale_factor,
                     width.unpack1("I") / @scale_factor, height.unpack1("I") / @scale_factor)
        end
        def frame=(bounds)
          raise Error, "window is closed" if closed?
          WindowState.new(frame: bounds, display_id: nil, maximized: false, fullscreen: false)
          raise ArgumentError, "X11 frame origin must be numeric" if bounds.x.nil?
          if @handle
            x(:XMoveResizeWindow, [P, L, I, I, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT], I, @display, @handle,
              (bounds.x * @scale_factor).round, (bounds.y * @scale_factor).round,
              (bounds.width * @scale_factor).round, (bounds.height * @scale_factor).round)
            x(:XFlush, [P], I, @display)
          end
          super
        end
        def state
          current = frame
          center = Point.new(current.x + current.width / 2, current.y + current.height / 2)
          display = displays.find { |candidate| candidate.bounds.contains?(center) } || displays.find(&:primary) || displays.first
          WindowState.new(frame: current, display_id: display&.id, maximized: maximized?, fullscreen: fullscreen?)
        end
        def maximized?
          return super if !@handle || closed?
          states = wm_states
          states.include?("_NET_WM_STATE_MAXIMIZED_VERT") && states.include?("_NET_WM_STATE_MAXIMIZED_HORZ")
        end
        def fullscreen? = @handle && !closed? ? wm_states.include?("_NET_WM_STATE_FULLSCREEN") : super
        def always_on_top? = @handle && !closed? ? wm_states.include?("_NET_WM_STATE_ABOVE") : super
        def minimized?
          return super if !@handle || closed?
          value = read_property(@handle, atom("WM_STATE"), delete: false)
          value.empty? ? @minimized : value.unpack1("L!") == 3
        end
        def wm_states
          read_property(@handle, atom("_NET_WM_STATE"), delete: false).unpack("L!*").map { |id| atom_name(id) }
        end
        def wm_state(action, *names)
          send_wm_message("_NET_WM_STATE", [action, atom(names.fetch(0)), names[1] ? atom(names[1]) : 0, 1, 0])
        end
        def send_wm_message(name, data)
          raise Error, "window is closed" if closed?
          event = "\0".b * 192
          event[0, 4] = [33].pack("i")
          event[24, 8] = [@display.to_i].pack("J")
          event[32, 8] = [@handle].pack("L!")
          event[40, 8] = [atom(name)].pack("L!")
          event[48, 4] = [32].pack("i")
          event[56, 40] = data.fill(0, data.length...5).pack("L!5")
          x(:XSendEvent, [P, L, I, L, P], I, @display, @root, 0, (1 << 19) | (1 << 20), event)
          x(:XFlush, [P], I, @display)
        end
        def maximize
          wm_state(1, "_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ")
          @maximized, @minimized = true, false
          notify_state_change
        end
        def minimize
          raise Error, "window is closed" if closed?
          x(:XIconifyWindow, [P, L, I], I, @display, @handle, @screen)
          x(:XFlush, [P], I, @display)
          @minimized = true
          notify_state_change
        end
        def restore
          wm_state(0, "_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ")
          wm_state(0, "_NET_WM_STATE_FULLSCREEN")
          x(:XMapRaised, [P, L], I, @display, @handle)
          x(:XFlush, [P], I, @display)
          @maximized = @minimized = @fullscreen = false
          notify_state_change
        end
        def always_on_top=(value)
          wm_state(value ? 1 : 0, "_NET_WM_STATE_ABOVE")
          @always_on_top = !!value
          notify_state_change
        end
        def tick
          poll_events unless closed?
          poll_appearance unless closed?
          Accessibility.poll(self) unless closed?
          raise @native_error if @native_error
          super
        end
        def run
          fd = x(:XConnectionNumber, [P], I, @display)
          io = IO.for_fd(fd, autoclose: false)
          until closed?
            tick
            IO.select([io], nil, nil, 0.05) unless dirty? || animation_active? || closed?
          end
        end
        def poll_events
          event = "\0".b * 192
          while !closed? && x(:XPending, [P], I, @display).positive?
            x(:XNextEvent, [P, P], I, @display, event)
            # XIM protocol replies target a private Xlib window, not our view.
            # None preserves the original event target for the registered filter.
            next if x(:XFilterEvent, [P, L], I, event, 0) != 0
            type = event.unpack1("i")
            if @randr_event && [@randr_event, @randr_event + 1].include?(type)
              refresh_scale
              request_frame
              next
            end
            case type
            when 2, 3 then key_event(event, type)
            when 4, 5, 6 then mouse_event(event, type)
            when 9 then x(:XSetICFocus, [P], V, @ic) if @ic
            when 10 then x(:XUnsetICFocus, [P], V, @ic) if @ic
            when 12 then request_frame
            when 22 then update_native_geometry
            when 28
              property_event(event)
              refresh_scale if event[40, 8].unpack1("L!") == atom("RESOURCE_MANAGER")
              notify_state_change if [atom("_NET_WM_STATE"), atom("WM_STATE")].include?(event[40, 8].unpack1("L!"))
            when 30 then selection_request(event)
            when 31
              name = event[56, 8].unpack1("L!")
              selection = event[40, 8].unpack1("L!")
              finish_drop(name) if selection == atom("XdndSelection")
              @selection_received = name if selection == atom("CLIPBOARD")
            when 33 then client_message(event)
            end
          end
          expire_outgoing_incr
        end
        def update_native_geometry
          current = frame
          old = @window_frame
          if current.width != content_size.width || current.height != content_size.height
            @suppress_state_change = true
            begin
              resize(current.width, current.height)
            ensure
              @suppress_state_change = false
            end
          end
          @window_frame = current
          @on_moved&.call([current.x, current.y]) if old.x != current.x || old.y != current.y
          notify_state_change if old != current
        end
        def modifiers(state) = [[4, "ctrl"], [8, "alt"], [1, "shift"], [64, "cmd"]].filter_map { |mask, name| name unless (state & mask).zero? }
        def key_event(event, type)
          state = event[80, 4].unpack1("I")
          keysym = x(:XLookupKeysym, [P, I], L, event, 0)
          name = x(:XKeysymToString, [L], P, keysym)
          key = name.null? ? "" : name.to_s.downcase
          key = {"return" => "enter", "escape" => "esc", "backspace" => "backspace", "prior" => "pageup", "next" => "pagedown"}.fetch(key, key)
          key = (modifiers(state) + [key]).join("-")
          input(type == 2 ? Input::KeyDown.new(key, false) : Input::KeyUp.new(key)) unless type == 2 && @preedit && !@preedit.empty?
          return unless type == 2 && (state & (4 | 64)).zero?
          bytes, symbol, status = "\0".b * 4096, [0].pack("L!"), [0].pack("i")
          length = if @ic
            x(:Xutf8LookupString, [P, P, P, I, P, P], I, @ic, event, bytes, bytes.bytesize, symbol, status)
          else
            x(:XLookupString, [P, P, I, P, P], I, event, bytes, bytes.bytesize, symbol, 0)
          end
          if length > bytes.bytesize
            bytes = "\0".b * length
            length = x(:Xutf8LookupString, [P, P, P, I, P, P], I, @ic, event, bytes, bytes.bytesize, symbol, status)
          end
          text = bytes.byteslice(0, [length, 0].max).force_encoding("UTF-8").scrub
          input(Input::TextInput.new(text)) unless text.empty? || text.match?(/\A[\x00-\x1f\x7f]+\z/)
        end
        def mouse_event(event, type)
          px, py = event[64, 8].unpack("i2")
          position = Point.new(px / @scale_factor, py / @scale_factor)
          state, button = event[80, 8].unpack("I2")
          if type == 4 && button == 1 && decorations != :native
            region = window_region_at(position)
            direction = resize_direction(position) unless region && region != :drag
            direction ||= 8 if region == :drag
            if direction
              x(:XUngrabPointer, [P, L], I, @display, 0)
              send_wm_message("_NET_WM_MOVERESIZE", [*event[72, 8].unpack("i2"), direction, button, 1])
              return
            end
          end
          mods = modifiers(state)
          if type == 4 && (4..7).cover?(button)
            delta = button <= 5 ? Point.new(0, button == 4 ? -40 : 40) : Point.new(button == 6 ? -40 : 40, 0)
            input(Input::ScrollWheel.new(position, delta, :changed, mods))
          elsif !(4..7).cover?(button) || type == 6
            button = {1 => :left, 2 => :middle, 3 => :right}.fetch(button, :other)
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            count = @last_click && @last_click[0] == button && now - @last_click[1] < 0.4 && (position.x - @last_click[2].x).abs < 4 && (position.y - @last_click[2].y).abs < 4 ? 2 : 1
            @last_click = [button, now, position] if type == 4
            input(type == 6 ? Input::MouseMove.new(position, mods) : type == 4 ? Input::MouseDown.new(position, button, mods, count) : Input::MouseUp.new(position, button, mods))
          end
        end
        def resize_direction(position)
          return if !resizable || content_size.width <= 0 || content_size.height <= 0
          left, right = position.x < 6, position.x >= content_size.width - 6
          top, bottom = position.y < 6, position.y >= content_size.height - 6
          return 0 if top && left
          return 2 if top && right
          return 4 if bottom && right
          return 6 if bottom && left
          return 1 if top
          return 3 if right
          return 5 if bottom
          7 if left
        end
        def setup_ime
          libc = FFI::Library.new(nil)
          libc.fn(:setlocale, [I, P], P).call(0, "")
          x(:XSetLocaleModifiers, [P], P, "")
          @im = x(:XOpenIM, [P] * 4, P, @display, 0, 0, 0)
          return if @im.null?
          function = @x.fn(:XCreateIC, [P, Fiddle::TYPE_VARIADIC], P)
          @preedit, @ime_callbacks = "", []
          callbacks = {
            "preeditStartCallback" => [I, ->(_data) { @preedit = ""; -1 }],
            "preeditDoneCallback" => [V, ->(_data) { @preedit = ""; input(Input::Composition.new("", [0, 0])) }],
            "preeditDrawCallback" => [V, ->(data) { preedit_draw(data) }],
            "preeditCaretCallback" => [V, ->(data) { input(Input::Composition.new(@preedit, [Fiddle::Pointer.new(data)[0, 4].unpack1("i"), 0])) }]
          }.map do |name, (result, handler)|
            callback = Fiddle::Closure::BlockCaller.new(result, [P, P, P]) do |_ic, _client, data|
              begin
                handler.call(data)
              rescue StandardError => error
                @native_error = error
                result == I ? 0 : nil
              end
            end
            record = [0, callback.to_i].pack("J2")
            @ime_callbacks << [callback, record]
            [P, name, P, record]
          end.flatten
          nested = @x.fn(:XVaCreateNestedList, [I, Fiddle::TYPE_VARIADIC], P).call(0, *callbacks, P, 0)
          @ic = function.call(@im, P, "inputStyle", L, 0x0402, P, "clientWindow", L, @handle, P, "focusWindow", L, @handle, P, "preeditAttributes", P, nested, P, 0)
          x(:XFree, [P], I, nested) unless nested.null?
          @ic = function.call(@im, P, "inputStyle", L, 0x0408, P, "clientWindow", L, @handle, P, "focusWindow", L, @handle, P, 0) if @ic.null?
          @ic = nil if @ic.null?
        end
        def preedit_draw(data)
          pointer = Fiddle::Pointer.new(data)
          caret, first, length = pointer[0, 12].unpack("i3")
          native_text = pointer[16, 8].unpack1("J")
          text = ""
          unless native_text.zero?
            descriptor = Fiddle::Pointer.new(native_text)
            count = descriptor[0, 2].unpack1("S")
            wide = descriptor[16, 4].unpack1("i") != 0
            string = Fiddle::Pointer.new(descriptor[24, 8].unpack1("J"))
            text = wide ? string[0, count * 4].unpack("I*").pack("U*") : string.to_s.force_encoding("UTF-8").scrub unless string.null?
          end
          characters = @preedit.chars
          characters[first, length] = text.chars
          @preedit = characters.join
          input(Input::Composition.new(@preedit, [caret, 0]))
        end
        def ime_state=(bounds)
          @ime_state = bounds
          return unless @ic && bounds.is_a?(Bounds)
          point = [(bounds.x * @scale_factor).round.clamp(-32_768, 32_767), (bounds.bottom * @scale_factor).round.clamp(-32_768, 32_767)].pack("s2")
          nested = @x.fn(:XVaCreateNestedList, [I, Fiddle::TYPE_VARIADIC], P).call(0, P, "spotLocation", P, point, P, 0)
          @x.fn(:XSetICValues, [P, Fiddle::TYPE_VARIADIC], P).call(@ic, P, "preeditAttributes", P, nested, P, 0)
          x(:XFree, [P], I, nested)
        end

        def property(window, name, type, bytes, format: 8)
          x(:XChangeProperty, [P, L, L, L, I, I, P, I], I, @display, window, name, type, format, 0, bytes, format == 8 ? bytes.bytesize : bytes.bytesize / Fiddle::SIZEOF_LONG)
        end
        def setup_display_events
          x(:XSelectInput, [P, L, L], I, @display, @root, 1 << 22)
          @randr = FFI::Library.new("libXrandr.so.2")
          base, error = [0].pack("i"), [0].pack("i")
          if @randr.fn(:XRRQueryExtension, [P, P, P], I).call(@display, base, error) != 0
            @randr_event = base.unpack1("i")
            @randr.fn(:XRRSelectInput, [P, L, I], V).call(@display, @root, 1 | 2 | 4 | 64)
          end
        rescue LoadError
          # X11 without RandR still gets global Xft DPI property notifications.
          @randr = nil
        end
        def refresh_scale
          resource = read_property(@root, atom("RESOURCE_MANAGER"), delete: false)
          factor = ((resource[/Xft\.dpi:\s*(\d+(?:\.\d+)?)/, 1]&.to_f || 96) / 96.0).clamp(1.0, 4.0)
          return if factor == @scale_factor
          width, height = content_size.width * @scale_factor, content_size.height * @scale_factor
          @scale_factor = factor
          resize(width / factor, height / factor)
        end
        def write_clipboard(items)
          unless items.is_a?(Array) && items.all? { |item| item.is_a?(Clipboard::Item) }
            raise TypeError, "clipboard items must be an Array of Clipboard::Item"
          end
          items.each do |item|
            item.formats.each_value { |data| raise Error, "X11 selection exceeds 16 MiB" if data.bytesize > 16_777_216 }
          end
          clear_outgoing_incr
          super
          @clipboard_formats = items.each_with_object({}) { |item, formats| item.formats.each { |type, data| formats[type] ||= data } }
          x(:XSetSelectionOwner, [P, L, L, L], I, @display, atom("CLIPBOARD"), @handle, 0)
          x(:XFlush, [P], I, @display)
          items
        end
        def clipboard=(value)
          super
        end
        def clipboard = read_clipboard(types: ["text/plain"]).formats.fetch("text/plain", "")
        def clipboard_types
          return super if owns_clipboard?
          offered_clipboard_targets.filter_map { |target| target_mime(target) }.uniq.freeze
        end
        def read_clipboard(types:)
          raise TypeError, "clipboard types must be an Array" unless types.is_a?(Array)
          return super if owns_clipboard?
          offered = offered_clipboard_targets
          formats = types.each_with_object({}) do |type, result|
            targets = type == "text/plain" ? %w[UTF8_STRING text/plain;charset=utf-8 text/plain STRING] : [type]
            target = targets.find { |name| offered.include?(name) }
            if target && (data = selection(target))
              data = data.dup.force_encoding("ISO-8859-1").encode("UTF-8") if target == "STRING"
              result[type] = data
            end
          end
          Clipboard::Content.new(formats)
        end
        def clipboard_paths
          self.class.file_paths(selection("text/uri-list").to_s)
        end
        def self.file_paths(bytes)
          bytes.lines.filter_map do |line|
            next if line.start_with?("#")
            uri = URI.parse(line.strip) rescue nil
            next unless uri&.scheme == "file" && [nil, "", "localhost"].include?(uri.host)
            path = URI::RFC2396_PARSER.unescape(uri.path).force_encoding("UTF-8")
            path if path.start_with?("/") && !path.include?("\0") && path.valid_encoding?
          end
        end
        def selection(target)
          return own_selection(target) if owns_clipboard?
          return nil if x(:XGetSelectionOwner, [P, L], L, @display, atom("CLIPBOARD")).zero?
          @selection_received = nil
          name = atom("ZANIAH_SELECTION")
          x(:XConvertSelection, [P, L, L, L, L, L], I, @display, atom("CLIPBOARD"), atom(target), name, @handle, 0)
          x(:XFlush, [P], I, @display)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
          while @selection_received.nil? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            poll_events
            IO.select([IO.for_fd(x(:XConnectionNumber, [P], I, @display), autoclose: false)], nil, nil, 0.01)
          end
          return nil unless @selection_received && @selection_received != 0
          read_property(@handle, name)
        end
        def read_property(window, name, delete: true)
          actual_type, format, length, remaining, pointer = [0].pack("L!"), [0].pack("i"), [0].pack("L!"), [0].pack("L!"), [0].pack("J")
          status = x(:XGetWindowProperty, [P, L, L, L, L, I, L, P, P, P, P, P], I, @display, window, name, 0, 4_194_304, delete ? 1 : 0, 0, actual_type, format, length, remaining, pointer)
          raise Error, "XGetWindowProperty failed" unless status.zero?
          data = Fiddle::Pointer.new(pointer.unpack1("J"))
          return "" if data.null?
          return read_incremental_property(name) if actual_type.unpack1("L!") == atom("INCR") && window == @handle
          raise Error, "X11 selection exceeds 16 MiB" unless remaining.unpack1("L!").zero?
          size = {8 => 1, 16 => 2, 32 => Fiddle::SIZEOF_LONG}.fetch(format.unpack1("i"), 0)
          raise Error, "X11 selection exceeds 16 MiB" if length.unpack1("L!") * size > 16_777_216
          data[0, length.unpack1("L!") * size]
        ensure
          x(:XFree, [P], I, data) if data && !data.null?
        end
        def client_message(event)
          type, data = event[40, 8].unpack1("L!"), event[56, 40].unpack("L!5")
          case type
          when atom("WM_PROTOCOLS") then close if data[0] == atom("WM_DELETE_WINDOW")
          when atom("XdndEnter")
            @drag_source = data[0]
            types = data[1].odd? ? read_property(@drag_source, atom("XdndTypeList"), delete: false).unpack("L!*") : data[2, 3]
            @drag_accept = types.include?(atom("text/uri-list"))
          when atom("XdndLeave") then @drag_source = nil
          when atom("XdndPosition")
            return unless data[0] == @drag_source
            root_x, root_y = [data[2] >> 16, data[2] & 0xffff].map { |n| n >= 0x8000 ? n - 0x10000 : n }
            left, top, child = [0].pack("i"), [0].pack("i"), [0].pack("L!")
            x(:XTranslateCoordinates, [P, L, L, I, I, P, P, P], I, @display, @root, @handle, root_x, root_y, left, top, child)
            @drag_position = Point.new(left.unpack1("i") / @scale_factor, top.unpack1("i") / @scale_factor)
            send_client_message(@drag_source, "XdndStatus", [@handle, @drag_accept ? 3 : 2, 0, 0, @drag_accept ? atom("XdndActionCopy") : 0])
          when atom("XdndDrop")
            return unless data[0] == @drag_source
            return finish_drop(0) unless @drag_accept
            x(:XConvertSelection, [P, L, L, L, L, L], I, @display, atom("XdndSelection"), atom("text/uri-list"), atom("ZANIAH_DROP"), @handle, data[2])
          end
        end
        def finish_drop(property_name)
          return unless @drag_source
          paths = property_name.zero? ? [] : self.class.file_paths(read_property(@handle, property_name))
          send_client_message(@drag_source, "XdndFinished", [@handle, paths.empty? ? 0 : 1, paths.empty? ? 0 : atom("XdndActionCopy"), 0, 0])
          @drag_source = nil
          input(Input::FileDrop.new(paths.freeze, @drag_position || Point.new(0, 0))) unless paths.empty?
        end
        def send_client_message(window, name, data)
          event = "\0".b * 192
          event[0, 4] = [33].pack("i")
          event[24, 24] = [@display.to_i, window, atom(name)].pack("J3")
          event[48, 4] = [32].pack("i")
          event[56, 40] = data.pack("L!5")
          x(:XSendEvent, [P, L, I, L, P], I, @display, window, 0, 0, event)
          x(:XFlush, [P], I, @display)
        end
        def selection_request(event)
          requestor, selection, target, prop, time = event[40, 40].unpack("L!5")
          prop = target if prop.zero?
          name = atom_name(target)
          data = selection == atom("CLIPBOARD") ? own_selection(name) : nil
          release_outgoing_incr([requestor, prop]) if @outgoing_incr&.key?([requestor, prop])
          if data
            if data.bytesize > 65_536
              @incr_subscriptions ||= Hash.new(0)
              if @incr_subscriptions[requestor].zero? && requestor != @handle
                x(:XSelectInput, [P, L, L], I, @display, requestor, 1 << 22)
              end
              @incr_subscriptions[requestor] += 1
              @outgoing_incr ||= {}
              @outgoing_incr[[requestor, prop]] = {data: data, offset: 0, type: target, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10}
              property(requestor, prop, atom("INCR"), [data.bytesize].pack("L!"), format: 32)
            else
              property(requestor, prop, name == "TARGETS" ? 4 : target, data, format: name == "TARGETS" ? 32 : 8)
            end
          else
            prop = 0
          end
          reply = "\0".b * 192
          reply[0, 4] = [31].pack("i")
          reply[24, 8] = [@display.to_i].pack("J")
          reply[32, 40] = [requestor, selection, target, prop, time].pack("L!5")
          x(:XSendEvent, [P, L, I, L, P], I, @display, requestor, 0, 0, reply)
          x(:XFlush, [P], I, @display)
        end
        def owns_clipboard?
          x(:XGetSelectionOwner, [P, L], L, @display, atom("CLIPBOARD")) == @handle
        end
        def offered_clipboard_targets
          bytes = selection("TARGETS")
          bytes ? bytes.unpack("L!*").map { |id| atom_name(id) } : []
        end
        def target_mime(target)
          return nil if target == "TARGETS" || target == "INCR"
          return "text/plain" if %w[UTF8_STRING STRING text/plain;charset=utf-8].include?(target)
          target if target.include?("/")
        end
        def own_selection(target)
          formats = @clipboard_formats || {}
          if target == "TARGETS"
            names = ["TARGETS", *formats.keys]
            names.concat(%w[UTF8_STRING text/plain;charset=utf-8]) if formats.key?("text/plain")
            names << "STRING" if latin1_text
            return names.uniq.map { |name| atom(name) }.pack("L!*")
          end
          return latin1_text if target == "STRING"
          return formats["text/plain"] if %w[UTF8_STRING text/plain;charset=utf-8].include?(target)
          formats[target]
        end
        def latin1_text
          @clipboard_formats&.fetch("text/plain", nil)&.encode("ISO-8859-1")&.b
        rescue Encoding::UndefinedConversionError
          nil
        end
        def atom_name(id)
          pointer = x(:XGetAtomName, [P, L], P, @display, id)
          return "" if pointer.null?
          pointer.to_s
        ensure
          x(:XFree, [P], I, pointer) if pointer && !pointer.null?
        end
        def property_event(event)
          window, name, state = event[32, 8].unpack1("L!"), event[40, 8].unpack1("L!"), event[56, 4].unpack1("i")
          if state.zero? && window == @handle && @incremental_read && @incremental_read[:name] == name
            chunk = read_property(@handle, name)
            @incremental_read[:done] = true if chunk.empty?
            @incremental_read[:data] << chunk
            raise Error, "X11 selection exceeds 16 MiB" if @incremental_read[:data].bytesize > 16_777_216
          elsif state == 1 && (transfer = @outgoing_incr&.[]([window, name]))
            chunk = transfer[:data].byteslice(transfer[:offset], 65_536) || "".b
            transfer[:offset] += chunk.bytesize
            property(window, name, transfer[:type], chunk)
            chunk.empty? ? release_outgoing_incr([window, name]) : transfer[:deadline] = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
            x(:XFlush, [P], I, @display)
          end
        end
        def release_outgoing_incr(key)
          return unless @outgoing_incr&.delete(key)
          requestor = key.first
          @incr_subscriptions[requestor] -= 1
          if @incr_subscriptions[requestor].zero?
            @incr_subscriptions.delete(requestor)
            x(:XSelectInput, [P, L, L], I, @display, requestor, 0) if requestor != @handle
          end
        end
        def clear_outgoing_incr
          @outgoing_incr&.keys&.each { |key| release_outgoing_incr(key) }
        end
        def expire_outgoing_incr(now = Process.clock_gettime(Process::CLOCK_MONOTONIC))
          @outgoing_incr&.each { |key, transfer| release_outgoing_incr(key) if transfer[:deadline] <= now }
        end
        def read_incremental_property(name)
          @incremental_read = {name: name, data: +"".b, done: false}
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
          io = IO.for_fd(x(:XConnectionNumber, [P], I, @display), autoclose: false)
          until @incremental_read[:done]
            raise Error, "X11 selection transfer timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            poll_events
            IO.select([io], nil, nil, 0.01) unless @incremental_read[:done]
          end
          @incremental_read[:data]
        ensure
          @incremental_read = nil
        end
        def cursor_style=(style)
          number = {arrow: 68, text: 152, pointer: 60, crosshair: 34, resize_horizontal: 108, resize_vertical: 116}.fetch(style)
          cursor = x(:XCreateFontCursor, [P, I], L, @display, number)
          x(:XDefineCursor, [P, L, L], I, @display, @handle, cursor)
          x(:XFreeCursor, [P, L], I, @display, cursor)
        end
        def prompt_for_paths(multiple: false, directories: false, save: false)
          command = ["zenity", "--file-selection", "--separator=\n"]
          command << "--multiple" if multiple
          command << "--directory" if directories
          command << "--save" << "--confirm-overwrite" if save
          output, status = Open3.capture2(*command)
          status.success? ? output.lines.map(&:chomp) : []
        rescue Errno::ENOENT
          raise Error, "file selection requires the desktop's zenity command"
        end
        def open_url(url)
          Process.detach(Process.spawn("xdg-open", url.to_s, out: File::NULL, err: File::NULL))
          true
        end
        def toggle_fullscreen
          wm_state(fullscreen? ? 0 : 1, "_NET_WM_STATE_FULLSCREEN")
          @fullscreen = !@fullscreen
          notify_state_change
        end
        def move_to_display(display)
          validate_display!(display)
          target = displays.find { |candidate| candidate.id == display.id }
          raise Error, "display is no longer available" unless target

          x_position = (target.bounds.x * target.scale_factor).round
          y_position = (target.bounds.y * target.scale_factor).round
          moved = x(:XMoveWindow, [P, L, I, I], I, @display, @handle, x_position, y_position)
          raise Error, "XMoveWindow failed" if moved.zero?
          x(:XFlush, [P], I, @display)
          true
        end
        def close
          return false if closed?
          @window_frame = frame
          @maximized, @minimized, @fullscreen, @always_on_top = maximized?, minimized?, fullscreen?, always_on_top?
          return false unless super
          clear_outgoing_incr
          Accessibility.close(self)
          close_appearance
          x(:XDestroyIC, [P], V, @ic) if @ic
          x(:XCloseIM, [P], I, @im) if @im && !@im.null?
          @gl.fn(:glXMakeCurrent, [P, L, P], I).call(@display, 0, 0)
          @gl.fn(:glXDestroyContext, [P, P], V).call(@display, @context)
          x(:XDestroyWindow, [P, L], I, @display, @handle)
          x(:XFreeColormap, [P, L], I, @display, @colormap)
          x(:XCloseDisplay, [P], I, @display)
          true
        end
      end
    end
  end
end
