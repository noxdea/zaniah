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
          protocol = [atom("WM_DELETE_WINDOW")].pack("L!")
          x(:XSetWMProtocols, [P, L, P, I], I, @display, @handle, protocol, 1)
          property(@handle, atom("XdndAware"), 4, [5].pack("L!"), format: 32)
          self.title = @title
          dpi = @x.fn(:XResourceManagerString, [P], P).call(@display)
          @scale_factor = dpi.null? ? 1.0 : (dpi.to_s[/Xft\.dpi:\s*(\d+(?:\.\d+)?)/, 1]&.to_f || 96) / 96.0
          @scale_factor = @scale_factor.clamp(1.0, 4.0)
          @content_size = Size.new(content_size.width / @scale_factor, content_size.height / @scale_factor)
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
        def tick
          poll_events unless closed?
          poll_appearance unless closed?
          raise @native_error if @native_error
          super
        end
        def run
          fd = x(:XConnectionNumber, [P], I, @display)
          io = IO.for_fd(fd, autoclose: false)
          until closed?
            tick
            IO.select([io], nil, nil, 0.05) unless dirty? || closed?
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
            when 22
              width, height = event[56, 8].unpack("i2")
              resize(width / @scale_factor, height / @scale_factor) if width.positive? && height.positive?
              @on_moved&.call(event[48, 8].unpack("i2"))
            when 28 then refresh_scale if event[40, 8].unpack1("L!") == atom("RESOURCE_MANAGER")
            when 30 then selection_request(event)
            when 31
              name = event[56, 8].unpack1("L!")
              event[40, 8].unpack1("L!") == atom("XdndSelection") ? finish_drop(name) : @selection_received = name
            when 33 then client_message(event)
            end
          end
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
        def clipboard=(value)
          @clipboard = value.to_s.encode("UTF-8")
          x(:XSetSelectionOwner, [P, L, L, L], I, @display, atom("CLIPBOARD"), @handle, 0)
          x(:XFlush, [P], I, @display)
        end
        def clipboard = selection("UTF8_STRING")
        def clipboard_paths
          self.class.file_paths(selection("text/uri-list"))
        end
        def self.file_paths(bytes)
          bytes.lines.filter_map do |line|
            next if line.start_with?("#")
            uri = URI.parse(line.strip) rescue nil
            next unless uri&.scheme == "file" && [nil, "", "localhost"].include?(uri.host)
            path = URI::DEFAULT_PARSER.unescape(uri.path).force_encoding("UTF-8")
            path if path.start_with?("/") && !path.include?("\0") && path.valid_encoding?
          end
        end
        def selection(target)
          return @clipboard.to_s if x(:XGetSelectionOwner, [P, L], L, @display, atom("CLIPBOARD")) == @handle
          @selection_received = nil
          name = atom("ZANIAH_SELECTION")
          x(:XConvertSelection, [P, L, L, L, L, L], I, @display, atom("CLIPBOARD"), atom(target), name, @handle, 0)
          x(:XFlush, [P], I, @display)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
          while @selection_received.nil? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            poll_events
            IO.select([IO.for_fd(x(:XConnectionNumber, [P], I, @display), autoclose: false)], nil, nil, 0.01)
          end
          return "" unless @selection_received && @selection_received != 0
          read_property(@handle, name).force_encoding("UTF-8").scrub
        end
        def read_property(window, name, delete: true)
          actual_type, format, length, remaining, pointer = [0].pack("L!"), [0].pack("i"), [0].pack("L!"), [0].pack("L!"), [0].pack("J")
          x(:XGetWindowProperty, [P, L, L, L, L, I, L, P, P, P, P, P], I, @display, window, name, 0, 4_194_304, delete ? 1 : 0, 0, actual_type, format, length, remaining, pointer)
          data = Fiddle::Pointer.new(pointer.unpack1("J"))
          return "" if data.null?
          raise Error, "incremental X11 clipboard transfer is not supported" if actual_type.unpack1("L!") == atom("INCR")
          raise Error, "X11 selection exceeds 16 MiB" unless remaining.unpack1("L!").zero?
          size = {8 => 1, 16 => 2, 32 => Fiddle::SIZEOF_LONG}.fetch(format.unpack1("i"), 0)
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
          if target == atom("TARGETS")
            property(requestor, prop, 4, [atom("TARGETS"), atom("UTF8_STRING"), atom("STRING")].pack("L!3"), format: 32)
          elsif [atom("UTF8_STRING"), atom("STRING")].include?(target)
            property(requestor, prop, target, @clipboard.to_s)
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
          event = "\0".b * 192
          event[0, 4] = [33].pack("i")
          event[24, 8] = [@display.to_i].pack("J")
          event[32, 8] = [@handle].pack("L!")
          event[40, 8] = [atom("_NET_WM_STATE")].pack("L!")
          event[48, 4] = [32].pack("i")
          event[56, 24] = [2, atom("_NET_WM_STATE_FULLSCREEN"), 0].pack("L!3")
          x(:XSendEvent, [P, L, I, L, P], I, @display, @root, 0, (1 << 19) | (1 << 20), event)
        end
        def close
          return false unless super
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
