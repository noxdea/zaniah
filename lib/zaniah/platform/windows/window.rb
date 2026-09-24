# frozen_string_literal: true

require "fiddle/import"
require_relative "../../ffi/library"
require_relative "../../gpu/open_gl"
require_relative "clipboard_data"
require_relative "native_menu"

module Zaniah
  module Platform
    module Windows
      def self.displays
        user, scale = FFI::Library.new("user32.dll"), FFI::Library.new("shcore.dll")
        ptype, int = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT
        result, error = [], nil
        callback = Fiddle::Closure::BlockCaller.new(int, [ptype, ptype, ptype, Fiddle::TYPE_INTPTR_T]) do |monitor, _dc, _rect, _data|
          begin
            info = [104].pack("I") + "\0".b * 100
            raise Error, "GetMonitorInfoW failed" if user.fn(:GetMonitorInfoW, [ptype, ptype], int).call(monitor, info).zero?
            x, y, right, bottom = info[4, 16].unpack("l4")
            dx, dy = [96].pack("I"), [96].pack("I")
            scale.fn(:GetDpiForMonitor, [ptype, int, ptype, ptype], int).call(monitor, 0, dx, dy)
            factor = dx.unpack1("I") / 96.0
            name = info[40, 64].force_encoding("UTF-16LE").encode("UTF-8").split("\0", 2).first
            result << Display.new(monitor.to_i, name, Bounds.new(x / factor, y / factor, (right - x) / factor, (bottom - y) / factor), factor, (info[36, 4].unpack1("I") & 1) != 0)
            1
          rescue StandardError => exception
            error = exception
            0
          end
        end
        user.fn(:EnumDisplayMonitors, [ptype, ptype, ptype, Fiddle::TYPE_INTPTR_T], int).call(0, 0, callback, 0)
        raise error if error
        result
      end
      module Types
        extend Fiddle::Importer
        WindowClass = struct ["unsigned int size", "unsigned int style", "void *procedure", "int class_extra", "int window_extra", "void *instance", "void *icon", "void *cursor", "void *background", "void *menu_name", "void *class_name", "void *small_icon"]
        PixelFormat = struct ["unsigned short size", "unsigned short version", "unsigned int flags", "unsigned char pixel_type", "unsigned char color_bits", "unsigned char red_bits", "unsigned char red_shift", "unsigned char green_bits", "unsigned char green_shift", "unsigned char blue_bits", "unsigned char blue_shift", "unsigned char alpha_bits", "unsigned char alpha_shift", "unsigned char accum_bits", "unsigned char accum_red_bits", "unsigned char accum_green_bits", "unsigned char accum_blue_bits", "unsigned char accum_alpha_bits", "unsigned char depth_bits", "unsigned char stencil_bits", "unsigned char aux_buffers", "unsigned char layer_type", "unsigned char reserved", "unsigned int layer_mask", "unsigned int visible_mask", "unsigned int damage_mask"]
        OpenFileName = struct ["unsigned int size", "void *owner", "void *instance", "void *filter", "void *custom_filter", "unsigned int max_custom_filter", "unsigned int filter_index", "void *file", "unsigned int max_file", "void *file_title", "unsigned int max_file_title", "void *initial_dir", "void *title", "unsigned int flags", "unsigned short file_offset", "unsigned short extension_offset", "void *default_extension", "intptr_t custom_data", "void *hook", "void *template_name", "void *reserved", "unsigned int reserved_size", "unsigned int flags_ex"]
      end

      class Window < Headless::Window
        def displays = Windows.displays
        I, U, P, N, V = Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOID
        INSTANCES = {}
        attr_reader :handle

        def initialize(gpu: :opengl, **options)
          raise Error, "native Windows backend requires a 64-bit Ruby" unless Fiddle::SIZEOF_VOIDP == 8
          super(**options)
          @user, @kernel, @gdi = FFI::Library.new("user32.dll"), FFI::Library.new("kernel32.dll"), FFI::Library.new("gdi32.dll")
          @shell, @imm, @gl = FFI::Library.new("shell32.dll"), FFI::Library.new("imm32.dll"), FFI::Library.new("opengl32.dll")
          @user.fn(:SetProcessDpiAwarenessContext, [P], I).call(-4)
          instance = @kernel.fn(:GetModuleHandleW, [P], P).call(0)
          @class_name = wide("ZaniahWindow#{object_id}")
          @procedure = Fiddle::Closure::BlockCaller.new(N, [P, U, N, N]) do |handle, message, wparam, lparam|
            window = INSTANCES[handle.to_i]
            if window
              window.native_callback { window.message(message, wparam, lparam) }
            else
              @user.fn(:DefWindowProcW, [P, U, N, N], N).call(handle, message, wparam, lparam)
            end
          end
          definition = Types::WindowClass.malloc(Fiddle::RUBY_FREE)
          definition.to_ptr[0, Types::WindowClass.size] = "\0" * Types::WindowClass.size
          definition.size, definition.style, definition.procedure = Types::WindowClass.size, 0x0023, @procedure
          definition.instance, definition.class_name = instance, Fiddle::Pointer[@class_name]
          definition.cursor = @user.fn(:LoadCursorW, [P, P], P).call(0, 32512)
          raise Error, "RegisterClassExW failed" if @user.fn(:RegisterClassExW, [P], I).call(definition).zero?
          @instance = instance
          style = decorations == :none ? (resizable ? 0x800F0000 : 0x80080000) : 0x00CF0000
          style &= ~0x00050000 unless resizable
          @handle = @user.fn(:CreateWindowExW, [U, P, P, U, I, I, I, I, P, P, P, P], P).call(transparent ? 0x00080000 : 0, @class_name, wide(@title), style, 100, 100, content_size.width.to_i, content_size.height.to_i, 0, 0, instance, 0)
          raise Error, "CreateWindowExW failed" if @handle.null?
          INSTANCES[@handle.to_i] = self
          @native_menu = NativeMenu.new(self, @user)
          @scale_factor = @user.fn(:GetDpiForWindow, [P], U).call(@handle) / 96.0
          client = "\0" * 16
          @user.fn(:GetClientRect, [P, P], I).call(@handle, client)
          _, _, width, height = client.unpack("l4")
          @content_size = Size.new(width / @scale_factor, height / @scale_factor)
          @dc = @user.fn(:GetDC, [P], P).call(@handle)
          @device.release
          @device = create_device(gpu)
          @shell.fn(:DragAcceptFiles, [P, I], V).call(@handle, 1)
          @user.fn(:ShowWindow, [P, I], I).call(@handle, 5)
          @user.fn(:UpdateWindow, [P], I).call(@handle)
        end
        def wide(text) = text.to_s.encode("UTF-16LE").b + "\0\0".b
        def create_device(backend)
          raise ArgumentError, "Win32 supports :opengl" unless [:opengl, :gl].include?(backend)
          descriptor = Types::PixelFormat.malloc(Fiddle::RUBY_FREE)
          descriptor.to_ptr[0, Types::PixelFormat.size] = "\0" * Types::PixelFormat.size
          descriptor.size, descriptor.version, descriptor.flags = Types::PixelFormat.size, 1, 0x25
          descriptor.color_bits, descriptor.alpha_bits = 32, 8
          format = @gdi.fn(:ChoosePixelFormat, [P, P], I).call(@dc, descriptor)
          raise Error, "ChoosePixelFormat failed" if format.zero?
          raise Error, "SetPixelFormat failed" if @gdi.fn(:SetPixelFormat, [P, I, P], I).call(@dc, format, descriptor).zero?
          temporary = @gl.fn(:wglCreateContext, [P], P).call(@dc)
          raise Error, "wglCreateContext failed" if temporary.null?
          @gl.fn(:wglMakeCurrent, [P, P], I).call(@dc, temporary)
          resolver = ->(name) { @gl.fn(:wglGetProcAddress, [P], P).call(name) }
          address = resolver.call("wglCreateContextAttribsARB")
          raise Error, "WGL_ARB_create_context unavailable" if address.to_i <= 3 || address.to_i == -1
          attributes = [0x2091, 3, 0x2092, 3, 0x9126, 1, 0].pack("i*")
          @context = Fiddle::Function.new(address, [P, P, P], P).call(@dc, 0, attributes)
          @gl.fn(:wglMakeCurrent, [P, P], I).call(0, 0)
          @gl.fn(:wglDeleteContext, [P], I).call(temporary)
          raise Error, "OpenGL 3.3 core context unavailable" if @context.null?
          make_current
          swap = resolver.call("wglSwapIntervalEXT")
          Fiddle::Function.new(swap, [I], I).call(1) if swap.to_i > 3
          GPU::OpenGL.new(self, library: @gl, resolver: resolver)
        end
        def make_current
          raise Error, "wglMakeCurrent failed" if @gl.fn(:wglMakeCurrent, [P, P], I).call(@dc, @context).zero?
        end
        def swap_buffers = @gdi.fn(:SwapBuffers, [P], I).call(@dc)
        def title=(title)
          super
          @user.fn(:SetWindowTextW, [P, P], I).call(@handle, wide(title)) if @handle
        end
        def tick
          @native_menu.sync(app&.menu_bar)
          event = "\0" * 48
          while !closed? && @user.fn(:PeekMessageW, [P, P, U, U, U], I).call(event, 0, 0, 0, 1) != 0
            @user.fn(:TranslateMessage, [P], I).call(event)
            @user.fn(:DispatchMessageW, [P], N).call(event)
          end
          raise @native_error if @native_error
          super
        end
        def run
          until closed?
            tick
            @user.fn(:MsgWaitForMultipleObjectsEx, [U, P, U, U, U], U).call(0, 0, 50, 0x04FF, 4) unless dirty? || animation_active? || closed?
          end
        end
        def native_callback
          yield
        rescue StandardError => error
          @native_error = error
          0
        end
        def modifiers
          [[0x11, "ctrl"], [0x12, "alt"], [0x10, "shift"], [0x5B, "cmd"]].filter_map do |code, name|
            name unless (@user.fn(:GetKeyState, [I], Fiddle::TYPE_SHORT).call(code) & 0x8000).zero?
          end
        end
        KEYS = {8 => "backspace", 9 => "tab", 13 => "enter", 27 => "esc", 32 => "space", 33 => "pageup", 34 => "pagedown", 35 => "end", 36 => "home", 37 => "left", 38 => "up", 39 => "right", 40 => "down", 46 => "delete"}.freeze
        def message(message, wparam, lparam)
          case message
          when 0x0010 then close; return 0
          when 0x0116 then return 0 if @native_menu&.prepare(wparam, 0) # WM_INITMENU
          when 0x0111 then return 0 if @native_menu&.command(wparam, lparam) # WM_COMMAND
          when 0x0117 then return 0 if @native_menu&.prepare(wparam, lparam) # WM_INITMENUPOPUP
          when 0x0083 then return 0 if decorations == :hidden_titlebar && !wparam.zero? # WM_NCCALCSIZE
          when 0x0084
            region = native_window_region(lparam)
            return region if region
          when 0x0024
            if min_size && !lparam.zero?
              Fiddle::Pointer.new(lparam)[24, 8] = [(min_size.width * @scale_factor).round, (min_size.height * @scale_factor).round].pack("l2")
              return 0
            end
          when 0x003d
            result = Accessibility::Windows.provider_result(self, wparam, lparam)
            return result if result
          when 0x0233
            dropped_files(wparam)
            return 0
          when 0x001a, 0x031a
            @on_appearance&.call(appearance)
            request_frame
          when 0x0005
            width, height = lparam & 0xffff, (lparam >> 16) & 0xffff
            resize(width / @scale_factor, height / @scale_factor) if width.positive? && height.positive?
          when 0x0003
            @on_moved&.call([signed16(lparam) / @scale_factor, signed16(lparam >> 16) / @scale_factor])
            notify_state_change
          when 0x02e0
            @scale_factor = (wparam & 0xffff) / 96.0
            left, top, right, bottom = Fiddle::Pointer.new(lparam)[0, 16].unpack("l4")
            @user.fn(:SetWindowPos, [P, P, I, I, I, I, U], I).call(@handle, 0, left, top, right - left, bottom - top, 0x0014)
          when 0x000f
            paint = "\0" * 128
            @user.fn(:BeginPaint, [P, P], P).call(@handle, paint)
            @user.fn(:EndPaint, [P, P], I).call(@handle, paint)
            request_frame
            return 0
          when 0x0100, 0x0101, 0x0104, 0x0105
            character = @user.fn(:MapVirtualKeyW, [U, U], U).call(wparam, 2) & 0x7fffffff
            name = KEYS[wparam] || ((0x70..0x87).cover?(wparam) ? "f#{wparam - 0x6f}" : character.between?(32, 0x10ffff) ? character.chr(Encoding::UTF_8).downcase : "key#{wparam}")
            stroke = (modifiers + [name]).join("-")
            input([0x0100, 0x0104].include?(message) ? Input::KeyDown.new(stroke, (lparam & (1 << 30)) != 0) : Input::KeyUp.new(stroke))
            return 0 unless [0x0104, 0x0105].include?(message)
          when 0x0102
            if (0xd800..0xdbff).cover?(wparam)
              @high_surrogate = wparam
            elsif (0xdc00..0xdfff).cover?(wparam) && @high_surrogate
              commit_character(0x10000 + ((@high_surrogate - 0xd800) << 10) + wparam - 0xdc00)
              @high_surrogate = nil
            else
              @high_surrogate = nil
              commit_character(wparam) unless (0xd800..0xdfff).cover?(wparam)
            end
            return 0
          when 0x0109
            return 1 if wparam == 0xffff
            commit_character(wparam)
            return 0
          when 0x010d, 0x010e then input(Input::Composition.new("", [0, 0]))
          when 0x010f
            with_ime do |context|
              if (lparam & 0x800) != 0
                input(Input::Composition.new("", [0, 0]))
                input(Input::TextInput.new(composition_string(context, 0x800)))
              end
              if (lparam & 8) != 0
                text = composition_string(context, 8)
                cursor = @imm.fn(:ImmGetCompositionStringW, [P, U, P, U], I).call(context, 0x80, 0, 0)
                input(Input::Composition.new(text, [[cursor, 0].max, 0]))
              end
            end
            return 0
          when 0x0200, 0x0201, 0x0202, 0x0203, 0x0204, 0x0205, 0x0206, 0x0207, 0x0208, 0x0209, 0x020a, 0x020e
            mouse_message(message, wparam, lparam)
            return 0
          end
          @user.fn(:DefWindowProcW, [P, U, N, N], N).call(@handle, message, wparam, lparam)
        end
        def signed16(number) = (number & 0xffff) >= 0x8000 ? (number & 0xffff) - 0x10000 : number & 0xffff
        def native_window_region(lparam)
          return if decorations == :native
          point = [signed16(lparam), signed16(lparam >> 16)].pack("l2")
          return if @user.fn(:ScreenToClient, [P, P], I).call(@handle, point).zero?
          x, y = point.unpack("l2").map { |value| value / @scale_factor }
          if resizable
            edge = 8
            left, right = x < edge, x >= content_size.width - edge
            top, bottom = y < edge, y >= content_size.height - edge
            return 13 if top && left
            return 14 if top && right
            return 16 if bottom && left
            return 17 if bottom && right
            return 10 if left
            return 11 if right
            return 12 if top
            return 15 if bottom
          end
          region = window_region_at(Point.new(x, y))
          {drag: 2, minimize: 8, maximize: 9, restore: 9, close: 20}[region]
        end
        def commit_character(code)
          input(Input::TextInput.new(code.chr(Encoding::UTF_8))) if code >= 32 && code != 127 && code <= 0x10ffff
        end
        def mouse_message(message, wparam, lparam)
          x, y = signed16(lparam), signed16(lparam >> 16)
          if [0x020a, 0x020e].include?(message)
            point = [x, y].pack("l2")
            @user.fn(:ScreenToClient, [P, P], I).call(@handle, point)
            x, y = point.unpack("l2")
          end
          position, mods = Point.new(x / @scale_factor, y / @scale_factor), modifiers
          if [0x020a, 0x020e].include?(message)
            amount = signed16(wparam >> 16) / 3.0
            input(Input::ScrollWheel.new(position, message == 0x020a ? Point.new(0, -amount) : Point.new(amount, 0), :changed, mods))
          elsif message == 0x0200
            input(Input::MouseMove.new(position, mods))
          else
            double = [0x0203, 0x0206, 0x0209].include?(message)
            down = double || [0x0201, 0x0204, 0x0207].include?(message)
            button = message <= 0x0203 ? :left : message <= 0x0206 ? :right : :middle
            down ? @user.fn(:SetCapture, [P], P).call(@handle) : @user.fn(:ReleaseCapture, [], I).call
            input(down ? Input::MouseDown.new(position, button, mods, double ? 2 : 1) : Input::MouseUp.new(position, button, mods))
          end
        end
        def with_ime
          context = @imm.fn(:ImmGetContext, [P], P).call(@handle)
          yield context unless context.null?
        ensure
          @imm.fn(:ImmReleaseContext, [P, P], I).call(@handle, context) if context && !context.null?
        end
        def composition_string(context, kind)
          size = @imm.fn(:ImmGetCompositionStringW, [P, U, P, U], I).call(context, kind, 0, 0)
          return "" unless size.positive?
          bytes = "\0" * size
          @imm.fn(:ImmGetCompositionStringW, [P, U, P, U], I).call(context, kind, bytes, size)
          bytes.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace)
        end
        def ime_state=(bounds)
          @ime_state = bounds
          return unless @handle && bounds.is_a?(Bounds)
          with_ime do |context|
            point = [(bounds.x * @scale_factor).to_i, (bounds.bottom * @scale_factor).to_i]
            form = [0x20, *point, 0, 0, 0, 0].pack("l7")
            @imm.fn(:ImmSetCompositionWindow, [P, P], I).call(context, form)
            candidate = [0, 0x40, *point, 0, 0, 0, 0].pack("l8")
            @imm.fn(:ImmSetCandidateWindow, [P, P], I).call(context, candidate)
          end
        end
        def clipboard = read_clipboard(types: ["text/plain"]).formats.fetch("text/plain", "")
        def clipboard=(text)
          value = text.to_s
          write_clipboard([Clipboard::Item.new("text/plain" => value)])
          value
        end

        def write_clipboard(items)
          stored = super
          formats = {}
          stored.each { |item| item.formats.each { |type, data| formats[type] ||= data } }
          allocated = []
          begin
            formats.each do |type, data|
              format, bytes = clipboard_payload(type, data)
              allocated << [format, clipboard_memory(bytes)]
            end
            with_clipboard do
              raise Error, "EmptyClipboard failed" if @user.fn(:EmptyClipboard, [], I).call.zero?
              allocated.each do |entry|
                raise Error, "SetClipboardData failed" if @user.fn(:SetClipboardData, [U, P], P).call(*entry).null?
                entry[1] = nil # SetClipboardData owns this HGLOBAL from here onward.
              end
            end
          ensure
            allocated.each { |_, memory| @kernel.fn(:GlobalFree, [P], P).call(memory) if memory }
          end
          stored
        end

        def read_clipboard(types:)
          raise TypeError, "clipboard types must be an Array" unless types.is_a?(Array)
          with_clipboard do
            formats = {}
            types.each do |type|
              data = read_clipboard_type(type)
              formats[type] = data if data
            end
            Clipboard::Content.new(formats)
          end
        end

        def clipboard_types
          with_clipboard do
            types = []
            format = 0
            loop do
              format = @user.fn(:EnumClipboardFormats, [U], U).call(format)
              break if format.zero?
              type = clipboard_type_name(format)
              types << type if type && !types.include?(type)
            end
            types.freeze
          end
        end

        def clipboard_payload(type, data)
          case type
          when "text/plain" then [13, wide(data)]
          when "text/html" then [clipboard_format("HTML Format"), ClipboardData.format_html(data) + "\0".b]
          when "image/png" then [clipboard_format("PNG"), data]
          when "text/uri-list"
            paths = ClipboardData.file_paths(data)
            paths ? [15, ClipboardData.hdrop(paths)] : [clipboard_format(type), data]
          else [clipboard_format(type), data]
          end
        end

        def clipboard_format(name)
          @clipboard_formats ||= {}
          @clipboard_formats[name] ||= begin
            format = @user.fn(:RegisterClipboardFormatW, [P], U).call(wide(name))
            raise Error, "RegisterClipboardFormatW failed for #{name}" if format.zero?
            format
          end
        end

        def clipboard_memory(bytes)
          memory = @kernel.fn(:GlobalAlloc, [U, Fiddle::TYPE_SIZE_T], P).call(2, [bytes.bytesize, 1].max)
          raise NoMemoryError, "clipboard allocation failed" if memory.null?
          begin
            pointer = @kernel.fn(:GlobalLock, [P], P).call(memory)
            raise Error, "GlobalLock failed" if pointer.null?
            pointer[0, bytes.bytesize] = bytes unless bytes.empty?
            pointer[0, 1] = "\0" if bytes.empty?
            @kernel.fn(:GlobalUnlock, [P], I).call(memory)
            memory
          rescue StandardError
            @kernel.fn(:GlobalFree, [P], P).call(memory)
            raise
          end
        end

        def read_clipboard_type(type)
          case type
          when "text/plain"
            data = clipboard_bytes(13)
            data&.unpack("v*")&.take_while { |value| !value.zero? }&.pack("v*")&.force_encoding(Encoding::UTF_16LE)&.encode(Encoding::UTF_8, invalid: :replace)
          when "text/html"
            data = clipboard_bytes(clipboard_format("HTML Format"))
            ClipboardData.parse_html(data) if data
          when "image/png"
            clipboard_bytes(clipboard_format("PNG")) || begin
              data = clipboard_bytes(17)
              ClipboardData.dibv5_to_png(data) if data
            end
          when "text/uri-list"
            paths = clipboard_paths_open
            paths.empty? ? clipboard_bytes(clipboard_format(type))&.force_encoding(Encoding::UTF_8)&.scrub : ClipboardData.uri_list(paths)
          else
            data = clipboard_bytes(clipboard_format(type))
            type.start_with?("text/") ? data&.force_encoding(Encoding::UTF_8)&.scrub : data
          end
        rescue ArgumentError
          nil # Ignore a malformed format supplied by another application.
        end

        def clipboard_bytes(format)
          memory = @user.fn(:GetClipboardData, [U], P).call(format)
          return nil if memory.null?
          pointer = @kernel.fn(:GlobalLock, [P], P).call(memory)
          return nil if pointer.null?
          size = @kernel.fn(:GlobalSize, [P], Fiddle::TYPE_SIZE_T).call(memory)
          pointer[0, size].b
        ensure
          @kernel.fn(:GlobalUnlock, [P], I).call(memory) if pointer && !pointer.null?
        end

        def clipboard_type_name(format)
          return "text/plain" if format == 13
          return "text/uri-list" if format == 15
          return "image/png" if format == 17
          bytes = "\0".b * 1024
          length = @user.fn(:GetClipboardFormatNameW, [U, P, I], I).call(format, bytes, bytes.bytesize / 2)
          return nil if length.zero?
          name = bytes.byteslice(0, length * 2).force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
          return "text/html" if name == "HTML Format"
          return "image/png" if name == "PNG"
          name if name.match?(%r{\A[^\s/]+/[^\s/]+\z})
        end
        def with_clipboard
          raise Error, "clipboard is busy" if @user.fn(:OpenClipboard, [P], I).call(@handle).zero?
          begin
            yield
          ensure
            @user.fn(:CloseClipboard, [], I).call
          end
        end
        def clipboard_paths
          with_clipboard { clipboard_paths_open }
        end
        def clipboard_paths_open
          drop = @user.fn(:GetClipboardData, [U], P).call(15)
          return [] if drop.null?
          count = @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, 0xffffffff, 0, 0)
          Array.new(count) do |i|
            size = @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, i, 0, 0)
            bytes = "\0" * ((size + 1) * 2)
            @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, i, bytes, size + 1)
            bytes.byteslice(0, size * 2).force_encoding("UTF-16LE").encode("UTF-8")
          end
        end
        def dropped_files(drop)
          count = @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, 0xffffffff, 0, 0)
          paths = Array.new(count) do |index|
            size = @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, index, 0, 0)
            bytes = "\0" * ((size + 1) * 2)
            @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, index, bytes, size + 1)
            bytes.byteslice(0, size * 2).force_encoding("UTF-16LE").encode("UTF-8")
          end
          point = "\0" * 8
          @shell.fn(:DragQueryPoint, [P, P], I).call(drop, point)
          x, y = point.unpack("l2")
          input(Input::FileDrop.new(paths.freeze, Point.new(x / @scale_factor, y / @scale_factor)))
        ensure
          @shell.fn(:DragFinish, [P], V).call(drop)
        end
        def appearance
          registry = FFI::Library.new("advapi32.dll")
          value, size = [1].pack("I"), [4].pack("I")
          result = registry.fn(:RegGetValueW, [P, P, P, U, P, P, P], I).call(-2147483647,
            wide("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"), wide("AppsUseLightTheme"), 0x10, 0, value, size)
          result.zero? && value.unpack1("I").zero? ? :dark : :light
        end
        def reduced_motion?
          enabled = [1].pack("I")
          result = @user.fn(:SystemParametersInfoW, [U, U, P, U], I).call(0x1042, 0, enabled, 0)
          !result.zero? && enabled.unpack1("I").zero?
        end
        def on_appearance(&block) = @on_appearance = block
        def context_menu(items, position: nil)
          return context_model_menu(items, position) if items.is_a?(Zaniah::Menu)
          return super(items, position: position || Point.new(0, 0)) if defined?(Zaniah::UI::ContextMenu)
          menu = @user.fn(:CreatePopupMenu, [], P).call
          raise Error, "CreatePopupMenu failed" if menu.null?
          items.each_with_index do |(label, action), index|
            @user.fn(:AppendMenuW, [P, U, N, P], I).call(menu, action ? 0 : 1, index + 1, wide(label))
          end
          point = position ? [(position.x * @scale_factor).round, (position.y * @scale_factor).round].pack("l2") : "\0" * 8
          position ? @user.fn(:ClientToScreen, [P, P], I).call(@handle, point) : @user.fn(:GetCursorPos, [P], I).call(point)
          x, y = point.unpack("l2")
          selected = @user.fn(:TrackPopupMenuEx, [P, U, I, I, P, P], U).call(menu, 0x182, x, y, @handle, 0)
          items[selected - 1][1]&.call if selected.positive?
        ensure
          @user.fn(:DestroyMenu, [P], I).call(menu) if menu && !menu.null?
        end
        def context_model_menu(model, position)
          menu = @user.fn(:CreatePopupMenu, [], P).call
          raise Error, "CreatePopupMenu failed" if menu.null?
          actions = {}
          options = {registry: app&.actions, keymap: dispatcher.keymap, platform: :windows}
          append_context_model_items(menu, model, model.resolve(**options), actions, options)
          point = position ? [(position.x * @scale_factor).round, (position.y * @scale_factor).round].pack("l2") : "\0" * 8
          position ? @user.fn(:ClientToScreen, [P, P], I).call(@handle, point) : @user.fn(:GetCursorPos, [P], I).call(point)
          x, y = point.unpack("l2")
          selected = @user.fn(:TrackPopupMenuEx, [P, U, I, I, P, P], U).call(menu, 0x182, x, y, @handle, 0)
          dispatcher.perform(actions[selected], source: :menu) if actions[selected]
        ensure
          @user.fn(:DestroyMenu, [P], I).call(menu) if menu && !menu.null?
        end
        def append_context_model_items(handle, model, items, actions, options)
          items.each do |item|
            if item.separator?
              flags, id, label = [0x0800, 0, nil]
            elsif item.submenu?
              child = @user.fn(:CreatePopupMenu, [], P).call
              raise Error, "CreatePopupMenu failed" if child.null?
              flags, id, label = [0x0010, child.to_i, item.title]
            else
              id = actions.length + 1
              raise Error, "too many context menu items" if id >= 0x8000
              enabled = dispatcher.available?(item.action) == :enabled
              flags = (enabled ? 0 : 1) | (dispatcher.checked?(item.action) ? 8 : 0)
              label = item.title
              actions[id] = enabled ? item.action : nil
            end
            appended = @user.fn(:AppendMenuW, [P, U, N, P], I).call(handle, flags, id, label && wide(label))
            if appended.zero?
              @user.fn(:DestroyMenu, [P], I).call(child) if child
              raise Error, "AppendMenuW failed"
            end
            append_context_model_items(child, model, model.children_for(item, **options), actions, options) if child
            child = nil
          end
        end
        def cursor_style=(style)
          id = {arrow: 32512, text: 32513, pointer: 32649, crosshair: 32515, resize_horizontal: 32644, resize_vertical: 32645}.fetch(style)
          cursor = @user.fn(:LoadCursorW, [P, P], P).call(0, id)
          @user.fn(:SetCursor, [P], P).call(cursor)
        end
        def prompt_for_paths(multiple: false, directories: false, save: false)
          return directory_dialog if directories
          dialog = Types::OpenFileName.malloc(Fiddle::RUBY_FREE)
          dialog.to_ptr[0, Types::OpenFileName.size] = "\0" * Types::OpenFileName.size
          bytes = "\0" * 131_072
          dialog.size, dialog.owner, dialog.file, dialog.max_file = Types::OpenFileName.size, @handle, Fiddle::Pointer[bytes], bytes.bytesize / 2
          dialog.flags = 0x00080000 | 0x00000800 | (multiple ? 0x200 : 0) | (save ? 2 : 0x1000)
          library = FFI::Library.new("comdlg32.dll")
          return [] if library.fn(save ? :GetSaveFileNameW : :GetOpenFileNameW, [P], I).call(dialog).zero?
          entries = bytes.force_encoding("UTF-16LE").encode("UTF-8").split("\0").take_while { |text| !text.empty? }
          entries.length > 1 ? entries.drop(1).map { |file| File.join(entries.first, file) } : entries
        end
        def directory_dialog
          # BROWSEINFOW is pointer-only except flags and the final image index.
          title = wide("Choose a directory")
          info = [@handle.to_i, 0, 0, Fiddle::Pointer[title].to_i, 0x41, 0, 0, 0].pack("J4Ix4J2Ix4")
          @shell.fn(:SHBrowseForFolderW, [P], P).call(info).then do |pidl|
            return [] if pidl.null?
            bytes = "\0" * 65_536
            ok = @shell.fn(:SHGetPathFromIDListEx, [P, P, U, U], I).call(pidl, bytes, bytes.bytesize / 2, 0)
            FFI::Library.new("ole32.dll").fn(:CoTaskMemFree, [P], V).call(pidl)
            ok.zero? ? [] : [bytes.force_encoding("UTF-16LE").encode("UTF-8").split("\0", 2).first]
          end
        end
        def open_url(url)
          @shell.fn(:ShellExecuteW, [P, P, P, P, P, I], P).call(@handle, wide("open"), wide(url), 0, 0, 1).to_i > 32
        end
        def frame
          rect = "\0" * 16
          raise Error, "GetWindowRect failed" if @user.fn(:GetWindowRect, [P, P], I).call(@handle, rect).zero?
          left, top, right, bottom = rect.unpack("l4")
          Bounds.new(left / @scale_factor, top / @scale_factor, (right - left) / @scale_factor, (bottom - top) / @scale_factor)
        end
        def frame=(bounds)
          WindowState.new(frame: bounds, display_id: nil, maximized: false, fullscreen: false)
          raise ArgumentError, "Windows frame origin must be numeric" if bounds.x.nil?
          result = @user.fn(:SetWindowPos, [P, P, I, I, I, I, U], I).call(@handle, 0,
            (bounds.x * @scale_factor).round, (bounds.y * @scale_factor).round,
            (bounds.width * @scale_factor).round, (bounds.height * @scale_factor).round, 0x0014)
          raise Error, "SetWindowPos failed" if result.zero?
          bounds
        end
        def maximized? = @user.fn(:IsZoomed, [P], I).call(@handle) != 0
        def minimized? = @user.fn(:IsIconic, [P], I).call(@handle) != 0
        def fullscreen? = !@restore_rect.nil?
        def always_on_top? = @always_on_top
        def always_on_top=(value)
          value = !!value
          result = @user.fn(:SetWindowPos, [P, P, I, I, I, I, U], I).call(@handle, value ? -1 : -2, 0, 0, 0, 0, 0x0013)
          raise Error, "SetWindowPos failed" if result.zero?
          @always_on_top = value
          notify_state_change
        end
        def state
          display = @user.fn(:MonitorFromWindow, [P, U], P).call(@handle, 2)
          WindowState.new(frame: frame, display_id: display.to_i, maximized: maximized?, fullscreen: fullscreen?)
        end
        def maximize = @user.fn(:ShowWindow, [P, I], I).call(@handle, 3)
        def minimize = @user.fn(:ShowWindow, [P, I], I).call(@handle, 6)
        def restore
          toggle_fullscreen if fullscreen?
          @user.fn(:ShowWindow, [P, I], I).call(@handle, 9)
        end
        def toggle_fullscreen
          if @restore_rect
            @user.fn(:SetWindowLongPtrW, [P, I, N], N).call(@handle, -16, @restore_style)
            left, top, right, bottom = @restore_rect.unpack("l4")
            @user.fn(:SetWindowPos, [P, P, I, I, I, I, U], I).call(@handle, 0, left, top, right - left, bottom - top, 0x0020)
            @restore_rect = nil
          else
            @restore_rect = "\0" * 16
            @restore_style = @user.fn(:GetWindowLongPtrW, [P, I], N).call(@handle, -16)
            @user.fn(:GetWindowRect, [P, P], I).call(@handle, @restore_rect)
            monitor = @user.fn(:MonitorFromWindow, [P, U], P).call(@handle, 2)
            info = [40].pack("I") + "\0" * 36
            @user.fn(:GetMonitorInfoW, [P, P], I).call(monitor, info)
            left, top, right, bottom = info[4, 16].unpack("l4")
            @user.fn(:SetWindowLongPtrW, [P, I, N], N).call(@handle, -16, 0x80000000)
            @user.fn(:SetWindowPos, [P, P, I, I, I, I, U], I).call(@handle, 0, left, top, right - left, bottom - top, 0x0020)
          end
        end
        def move_to_display(display)
          validate_display!(display)
          target = displays.find { |candidate| candidate.id == display.id }
          raise Error, "display is no longer available" unless target

          monitor = "\0" * 104
          monitor[0, 4] = [104].pack("I")
          raise Error, "GetMonitorInfoW failed" if @user.fn(:GetMonitorInfoW, [P, P], I).call(target.id, monitor).zero?
          left, top = monitor[4, 8].unpack("l2")
          flags = 0x0001 | 0x0004 | 0x0010 # SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
          moved = @user.fn(:SetWindowPos, [P, P, I, I, I, I, U], I).call(@handle, 0, left, top, 0, 0, flags)
          raise Error, "SetWindowPos failed" if moved.zero?

          true
        end
        def close
          return false unless super
          @native_menu&.close
          Accessibility.close(self)
          @gl.fn(:wglMakeCurrent, [P, P], I).call(0, 0)
          @gl.fn(:wglDeleteContext, [P], I).call(@context)
          @user.fn(:ReleaseDC, [P, P], I).call(@handle, @dc)
          INSTANCES.delete(@handle.to_i)
          @user.fn(:DestroyWindow, [P], I).call(@handle)
          @user.fn(:UnregisterClassW, [P, P], I).call(@class_name, @instance)
          true
        end
      end
    end
  end
end
