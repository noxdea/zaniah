# frozen_string_literal: true

require "fiddle/import"
require_relative "../../ffi/library"
require_relative "../../gpu/open_gl"

module Zaniah
  module Platform
    module Windows
      def self.displays
        user, scale = FFI::Library.new("user32.dll"), FFI::Library.new("shcore.dll")
        ptype, int, uint = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT
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
          @handle = @user.fn(:CreateWindowExW, [U, P, P, U, I, I, I, I, P, P, P, P], P).call(0, @class_name, wide(@title), 0x00CF0000, 100, 100, content_size.width.to_i, content_size.height.to_i, 0, 0, instance, 0)
          raise Error, "CreateWindowExW failed" if @handle.null?
          INSTANCES[@handle.to_i] = self
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
          when 0x0233
            dropped_files(wparam)
            return 0
          when 0x001a, 0x031a
            @on_appearance&.call(appearance)
            request_frame
          when 0x0005
            width, height = lparam & 0xffff, (lparam >> 16) & 0xffff
            resize(width / @scale_factor, height / @scale_factor) if width.positive? && height.positive?
          when 0x0003 then @on_moved&.call([signed16(lparam), signed16(lparam >> 16)])
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
        def clipboard
          with_clipboard do
            memory = @user.fn(:GetClipboardData, [U], P).call(13)
            next "" if memory.null?
            pointer = @kernel.fn(:GlobalLock, [P], P).call(memory)
            next "" if pointer.null?
            size = @kernel.fn(:GlobalSize, [P], Fiddle::TYPE_SIZE_T).call(memory)
            values = pointer[0, size].unpack("v*").take_while { |value| !value.zero? }
            @kernel.fn(:GlobalUnlock, [P], I).call(memory)
            values.pack("v*").force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace)
          end
        end
        def clipboard=(text)
          bytes = wide(text)
          with_clipboard do
            memory = @kernel.fn(:GlobalAlloc, [U, Fiddle::TYPE_SIZE_T], P).call(2, bytes.bytesize)
            raise NoMemoryError, "clipboard allocation failed" if memory.null?
            pointer = @kernel.fn(:GlobalLock, [P], P).call(memory)
            pointer[0, bytes.bytesize] = bytes
            @kernel.fn(:GlobalUnlock, [P], I).call(memory)
            @user.fn(:EmptyClipboard, [], I).call
            result = @user.fn(:SetClipboardData, [U, P], P).call(13, memory)
            if result.null?
              @kernel.fn(:GlobalFree, [P], P).call(memory)
              raise Error, "SetClipboardData failed"
            end
          end
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
          with_clipboard do
            drop = @user.fn(:GetClipboardData, [U], P).call(15)
            next [] if drop.null?
            count = @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, 0xffffffff, 0, 0)
            Array.new(count) do |i|
              size = @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, i, 0, 0)
              bytes = "\0" * ((size + 1) * 2)
              @shell.fn(:DragQueryFileW, [P, U, P, U], U).call(drop, i, bytes, size + 1)
              bytes.byteslice(0, size * 2).force_encoding("UTF-16LE").encode("UTF-8")
            end
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
        def toggle_fullscreen
          if @restore_rect
            @user.fn(:SetWindowLongPtrW, [P, I, N], N).call(@handle, -16, 0x00CF0000)
            left, top, right, bottom = @restore_rect.unpack("l4")
            @user.fn(:SetWindowPos, [P, P, I, I, I, I, U], I).call(@handle, 0, left, top, right - left, bottom - top, 0x0020)
            @restore_rect = nil
          else
            @restore_rect = "\0" * 16
            @user.fn(:GetWindowRect, [P, P], I).call(@handle, @restore_rect)
            monitor = @user.fn(:MonitorFromWindow, [P, U], P).call(@handle, 2)
            info = [40].pack("I") + "\0" * 36
            @user.fn(:GetMonitorInfoW, [P, P], I).call(monitor, info)
            left, top, right, bottom = info[4, 16].unpack("l4")
            @user.fn(:SetWindowLongPtrW, [P, I, N], N).call(@handle, -16, 0x80000000)
            @user.fn(:SetWindowPos, [P, P, I, I, I, I, U], I).call(@handle, 0, left, top, right - left, bottom - top, 0x0020)
          end
        end
        def close
          return false unless super
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
