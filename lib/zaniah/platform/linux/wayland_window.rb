# frozen_string_literal: true

require_relative "../../ffi/wayland"
require_relative "../../gpu/open_gl"
require_relative "appearance_aware"
require "open3"
require "uri"

module Zaniah
  module Platform
    module Linux
      class WaylandWindow < Headless::Window
        include AppearanceAware
        def displays = Linux.displays(display_server: :wayland)
        P, I, U, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOID
        GLOBALS = {"wl_compositor" => 4, "wl_shm" => 1, "wl_seat" => 5, "wl_output" => 2,
                   "wl_data_device_manager" => 3, "xdg_wm_base" => 1,
                   "zwp_text_input_manager_v3" => 1, "zxdg_decoration_manager_v1" => 1}.freeze
        attr_reader :handle
        def initialize(gpu: :opengl, **options)
          super(**options)
          raise Error, "traffic_lights is only supported on macOS" if traffic_lights
          @connection, @globals, @outputs, @offers = FFI::Wayland.new, {}, {}, {}
          @offer_actions = {}
          @entered_outputs = []
          @position, @modifiers, @serial = Point.new(0, 0), [], 0
          registry = @connection.request(@connection.display, 1, 0, new_interface: "wl_registry", version: 1)
          @connection.listen(registry, [
            [[U, P, U], ->(_registry, name, interface, version) { registry_global(registry, name, interface.to_s, version) }],
            [[U], ->(_registry, name) { @outputs.delete(name) }]
          ])
          @connection.roundtrip
          %w[wl_compositor xdg_wm_base].each { |name| raise Error, "Wayland compositor lacks #{name}" unless @globals[name] }
          @handle = @connection.request(@globals["wl_compositor"], 0, 0, new_interface: "wl_surface")
          @connection.listen(@handle, [
            [[P], ->(_surface, output) { @entered_outputs |= [output.to_i]; output_scale }],
            [[P], ->(_surface, output) { @entered_outputs.delete(output.to_i); output_scale }]
          ])
          @shell_surface = @connection.request(@globals["xdg_wm_base"], 2, 0, @handle, new_interface: "xdg_surface")
          @connection.listen(@shell_surface, [[[U], ->(surface, serial) { @connection.request(surface, 4, serial); @configured = true; request_frame }]])
          @toplevel = @connection.request(@shell_surface, 1, 0, new_interface: "xdg_toplevel")
          @connection.listen(@toplevel, [
            [[I, I, P], ->(_toplevel, width, height, states) { toplevel_configure(width, height, states) }],
            [[], ->(_toplevel) { @close_requested = true }]
          ])
          @connection.request(@toplevel, 2, @title)
          @connection.request(@toplevel, 3, "org.zaniah.app")
          minimum = resizable ? min_size : content_size
          @connection.request(@toplevel, 8, minimum.width.ceil, minimum.height.ceil) if minimum
          @connection.request(@toplevel, 7, content_size.width.ceil, content_size.height.ceil) unless resizable
          if (manager = @globals["zxdg_decoration_manager_v1"])
            @decoration = @connection.request(manager, 1, 0, @toplevel, new_interface: "zxdg_toplevel_decoration_v1")
            @connection.listen(@decoration, [[[U], nil]])
            @connection.request(@decoration, 1, decorations == :native ? 2 : 1)
          end
          setup_text_input
          setup_clipboard
          @connection.request(@handle, 6)
          @connection.roundtrip
          raise Error, "Wayland did not configure the initial surface" unless @configured
          @device.release
          @device = create_device(gpu)
        rescue StandardError, LoadError
          cleanup_native
          raise
        end
        def registry_global(registry, name, interface, version)
          return unless GLOBALS.key?(interface)
          object = @connection.request(registry, 0, name, interface, [version, GLOBALS[interface]].min, 0,
                                       new_interface: interface, version: [version, GLOBALS[interface]].min)
          if interface == "wl_output"
            @outputs[name] = [object, 1]
            @connection.listen(object, [
              [[I, I, I, I, I, P, P, I], nil], [[U, I, I, I], nil], [[], nil],
              [[I], ->(_output, scale) { @outputs[name][1] = scale; output_scale if @handle }]
            ])
          else
            @globals[interface] = object
          end
          case interface
          when "xdg_wm_base"
            @connection.listen(object, [[[U], ->(shell, serial) { @connection.request(shell, 3, serial) }]])
          when "wl_seat"
            @connection.listen(object, [[[U], ->(seat, capabilities) { seat_capabilities(seat, capabilities) }], [[P], nil]])
          end
        end
        def output_scale
          active = @outputs.values.select { |value| @entered_outputs.include?(value[0].to_i) }
          return if active.empty? || !@handle
          scale = [active.map(&:last).max, 1].max
          return if scale == @scale_factor
          @scale_factor = scale
          @connection.request(@handle, 8, scale)
          resize(content_size.width, content_size.height)
        end
        def resize(width, height)
          if @egl_window
            @wayland_egl.fn(:wl_egl_window_resize, [P, I, I, I, I], V).call(@egl_window, (width * @scale_factor).round, (height * @scale_factor).round, 0, 0)
          end
          super
        end
        def frame = Bounds.new(nil, nil, content_size.width, content_size.height)
        def frame=(bounds)
          WindowState.new(frame: bounds, display_id: nil, maximized: false, fullscreen: false)
          raise Error, "Wayland does not support arbitrary window positioning" unless bounds.x.nil? && bounds.y.nil?
          resize(bounds.width, bounds.height)
          bounds
        end
        def state
          display_id = @outputs&.find { |_id, (output, _scale)| @entered_outputs&.include?(output.to_i) }&.first
          WindowState.new(frame: frame, display_id: display_id, maximized: @maximized, fullscreen: @fullscreen)
        end
        def restore_state(saved)
          raise Error, "Wayland cannot programmatically restore a minimized window" if @minimized
          saved = WindowState.from_h(saved)
          self.frame = Bounds.new(nil, nil, saved.frame.width, saved.frame.height)
          @connection.request(@toplevel, 10)
          @connection.request(@toplevel, 12)
          if saved.maximized
            @connection.request(@toplevel, 9)
          elsif saved.fullscreen
            @connection.request(@toplevel, 11, 0)
          end
          @maximized, @minimized, @fullscreen = saved.maximized, false, !saved.maximized && saved.fullscreen
          notify_state_change
          state
        end
        def maximize
          @connection.request(@toplevel, 9)
          @maximized, @minimized = true, false
          notify_state_change
        end
        def minimize
          @connection.request(@toplevel, 13)
          @minimized = true
          notify_state_change
        end
        def restore
          raise Error, "Wayland cannot programmatically restore a minimized window" if @minimized
          @connection.request(@toplevel, 10)
          @connection.request(@toplevel, 12)
          @maximized = @minimized = @fullscreen = false
          notify_state_change
        end
        def always_on_top=(value)
          raise Error, "Wayland does not support always-on-top windows" if value
          @always_on_top = false
        end
        def toplevel_configure(width, height, states)
          flags = if states && !states.null?
            size, _allocation, data = Fiddle::Pointer.new(states)[0, Fiddle::SIZEOF_VOIDP * 3].unpack("J3")
            size <= 256 && data != 0 ? Fiddle::Pointer.new(data)[0, size].unpack("L<*") : []
          else
            []
          end
          old = [content_size, @maximized, @fullscreen, @minimized]
          @maximized, @fullscreen = flags.include?(1), flags.include?(2)
          @minimized = false if flags.include?(4)
          if width.positive? && height.positive? && (width != content_size.width || height != content_size.height)
            @suppress_state_change = true
            begin
              resize(width, height)
            ensure
              @suppress_state_change = false
            end
          end
          notify_state_change if old != [content_size, @maximized, @fullscreen, @minimized]
        end
        def create_device(backend)
          raise ArgumentError, "Wayland supports :opengl" unless [:gl, :opengl].include?(backend)
          @egl, @wayland_egl = FFI::Library.new("libEGL.so.1"), FFI::Library.new("libwayland-egl.so.1")
          @egl_display = @egl.fn(:eglGetDisplay, [P], P).call(@connection.display)
          major, minor = [0].pack("i"), [0].pack("i")
          egl_check(@egl.fn(:eglInitialize, [P, P, P], U).call(@egl_display, major, minor), "eglInitialize")
          egl_check(@egl.fn(:eglBindAPI, [U], U).call(0x30A2), "eglBindAPI OpenGL")
          attrs = [0x3024, 8, 0x3023, 8, 0x3022, 8, 0x3021, 8, 0x3033, 4, 0x3040, 8, 0x3038].pack("i*")
          config, count = [0].pack("J"), [0].pack("i")
          egl_check(@egl.fn(:eglChooseConfig, [P, P, P, I, P], U).call(@egl_display, attrs, config, 1, count), "eglChooseConfig")
          raise Error, "no EGL OpenGL window configuration" if count.unpack1("i").zero?
          config = config.unpack1("J")
          attributes = [0x3098, 3, 0x30fb, 3, 0x30fd, 1, 0x3038].pack("i*")
          @egl_context = @egl.fn(:eglCreateContext, [P, P, P, P], P).call(@egl_display, config, 0, attributes)
          raise Error, "EGL OpenGL 3.3 core context unavailable" if @egl_context.null?
          @egl_window = @wayland_egl.fn(:wl_egl_window_create, [P, I, I], P).call(@handle, (content_size.width * @scale_factor).round, (content_size.height * @scale_factor).round)
          @egl_surface = @egl.fn(:eglCreateWindowSurface, [P, P, P, P], P).call(@egl_display, config, @egl_window, 0)
          raise Error, "eglCreateWindowSurface failed" if @egl_surface.null?
          make_current
          @egl.fn(:eglSwapInterval, [P, I], U).call(@egl_display, 1)
          GPU::OpenGL.new(self, library: FFI::Library.new("libGL.so.1"), resolver: ->(name) { @egl.fn(:eglGetProcAddress, [P], P).call(name) })
        end
        def egl_check(value, name)
          raise Error, "#{name}: EGL error 0x#{@egl.fn(:eglGetError, [], U).call.to_s(16)}" if value.zero?
        end
        def make_current = egl_check(@egl.fn(:eglMakeCurrent, [P] * 4, U).call(@egl_display, @egl_surface, @egl_surface, @egl_context), "eglMakeCurrent")
        def swap_buffers = egl_check(@egl.fn(:eglSwapBuffers, [P, P], U).call(@egl_display, @egl_surface), "eglSwapBuffers")
        def title=(title)
          super
          @connection.request(@toplevel, 2, title) if @toplevel
        end
        def tick
          return if closed?
          @connection.poll
          poll_appearance
          Accessibility.poll(self)
          return close if @close_requested
          finish_drop if @pending_drop
          if @repeat_key && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @repeat_at
            keyboard_key(@repeat_key, 1, held: true)
            @repeat_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0 / @repeat_rate
          end
          super
        end
        def run
          until closed?
            @connection.poll(timeout: dirty? || animation_active? ? 0 : 0.05)
            tick
          end
        end
        def seat_capabilities(seat, capabilities)
          if (capabilities & 1) != 0 && !@pointer
            @pointer = @connection.request(seat, 0, 0, new_interface: "wl_pointer")
            @connection.listen(@pointer, [
              [[U, P, I, I], ->(_pointer, serial, _surface, x, y) { @serial = @pointer_serial = serial; @position = Point.new(x / 256.0, y / 256.0); self.cursor_style = :arrow }],
              [[U, P], nil],
              [[U, I, I], ->(_pointer, _time, x, y) { @position = Point.new(x / 256.0, y / 256.0); input(Input::MouseMove.new(@position, @modifiers)) }],
              [[U, U, U, U], ->(_pointer, serial, _time, button, state) { @serial = serial; pointer_button(button, state) }],
              [[U, U, I], ->(_pointer, _time, axis, value) { input(Input::ScrollWheel.new(@position, axis.zero? ? Point.new(0, value / 256.0) : Point.new(value / 256.0, 0), :changed, @modifiers)) }],
              [[], nil], [[U], nil], [[U, U], nil], [[U, I], nil]
            ])
          end
          if (capabilities & 2) != 0 && !@keyboard
            @keyboard = @connection.request(seat, 1, 0, new_interface: "wl_keyboard")
            @xkb = FFI::Library.new("libxkbcommon.so.0")
            @connection.listen(@keyboard, [
              [[U, I, U], ->(_keyboard, format, fd, size) { keyboard_map(format, fd, size) }],
              [[U, P, P], ->(_keyboard, serial, _surface, _keys) { @serial = serial }],
              [[U, P], ->(_keyboard, _serial, _surface) { @repeat_key = nil; @modifiers = [] }],
              [[U, U, U, U], ->(_keyboard, serial, _time, key, state) { @serial = serial; keyboard_key(key, state) }],
              [[U, U, U, U, U], ->(_keyboard, serial, depressed, latched, locked, group) { @serial = serial; keyboard_modifiers(depressed, latched, locked, group) }],
              [[I, I], ->(_keyboard, rate, delay) { @repeat_rate, @repeat_delay = rate, delay }]
            ])
          end
        end
        def pointer_button(code, state)
          button = {0x110 => :left, 0x111 => :right, 0x112 => :middle}.fetch(code, :other)
          if state == 1 && button == :left && decorations != :native && native_window_drag
            return
          end
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          count = @last_click && @last_click[0] == code && now - @last_click[1] < 0.4 && (@position.x - @last_click[2].x).abs < 4 && (@position.y - @last_click[2].y).abs < 4 ? 2 : 1
          @last_click = [code, now, @position] if state == 1
          input(state == 1 ? Input::MouseDown.new(@position, button, @modifiers, count) : Input::MouseUp.new(@position, button, @modifiers))
        end
        def native_window_drag
          seat = @globals["wl_seat"]
          return false unless seat && @serial.positive?
          region = window_region_at(@position)
          return false if region && region != :drag
          edge = resize_edge(@position)
          if edge
            @connection.request(@toplevel, 6, seat, @serial, edge)
          elsif region == :drag
            @connection.request(@toplevel, 5, seat, @serial)
          else
            return false
          end
          true
        end
        def resize_edge(position)
          return unless resizable && content_size.width.positive? && content_size.height.positive?
          left, right = position.x < 6, position.x >= content_size.width - 6
          top, bottom = position.y < 6, position.y >= content_size.height - 6
          return 5 if top && left
          return 9 if top && right
          return 10 if bottom && right
          return 6 if bottom && left
          return 1 if top
          return 8 if right
          return 2 if bottom
          4 if left
        end
        def keyboard_map(format, fd, size)
          io = IO.for_fd(fd)
          return unless format == 1
          raise Error, "Wayland keymap exceeds size limit" if size > 16_777_216
          source = io.read(size)
          @xkb.fn(:xkb_state_unref, [P], V).call(@key_state) if @key_state
          @xkb.fn(:xkb_keymap_unref, [P], V).call(@keymap) if @keymap
          @key_context ||= @xkb.fn(:xkb_context_new, [I], P).call(0)
          @keymap = @xkb.fn(:xkb_keymap_new_from_string, [P, P, I, I], P).call(@key_context, source, 1, 0)
          raise Error, "invalid Wayland XKB keymap" if @keymap.null?
          @key_state = @xkb.fn(:xkb_state_new, [P], P).call(@keymap)
        ensure
          io&.close
        end
        def keyboard_modifiers(depressed, latched, locked, group)
          return unless @key_state
          @xkb.fn(:xkb_state_update_mask, [P, U, U, U, U, U, U], U).call(@key_state, depressed, latched, locked, 0, 0, group)
          @modifiers = {"Control" => "ctrl", "Mod1" => "alt", "Shift" => "shift", "Mod4" => "cmd"}.filter_map do |native, key|
            key if @xkb.fn(:xkb_state_mod_name_is_active, [P, P, U], I).call(@key_state, native, 8) == 1
          end
        end
        def keyboard_key(code, state, held: false)
          return unless @key_state
          unless held
            if state == 1 && @repeat_rate.to_i.positive? && @xkb.fn(:xkb_keymap_key_repeats, [P, U], I).call(@keymap, code + 8) == 1
              @repeat_key, @repeat_at = code, Process.clock_gettime(Process::CLOCK_MONOTONIC) + @repeat_delay / 1000.0
            elsif state.zero? && @repeat_key == code
              @repeat_key = nil
            end
          end
          symbol = @xkb.fn(:xkb_state_key_get_one_sym, [P, U], U).call(@key_state, code + 8)
          bytes = "\0" * 128
          @xkb.fn(:xkb_keysym_get_name, [U, P, Fiddle::TYPE_SIZE_T], I).call(symbol, bytes, bytes.bytesize)
          key = bytes.split("\0", 2).first.downcase
          key = {"return" => "enter", "escape" => "esc", "prior" => "pageup", "next" => "pagedown"}.fetch(key, key)
          stroke = (@modifiers + [key]).join("-")
          input(state == 1 ? Input::KeyDown.new(stroke, held) : Input::KeyUp.new(stroke)) unless state == 1 && @composing
          return unless state == 1 && !@composing && (@modifiers & %w[ctrl cmd]).empty?
          length = @xkb.fn(:xkb_state_key_get_utf8, [P, U, P, Fiddle::TYPE_SIZE_T], I).call(@key_state, code + 8, bytes, bytes.bytesize)
          text = bytes.byteslice(0, [length, 0].max).force_encoding("UTF-8")
          input(Input::TextInput.new(text)) unless text.empty? || text.match?(/\A[\x00-\x1f\x7f]+\z/)
        end
        def setup_text_input
          manager, seat = @globals.values_at("zwp_text_input_manager_v3", "wl_seat")
          return unless manager && seat
          @text_input = @connection.request(manager, 1, 0, seat, new_interface: "zwp_text_input_v3")
          @text_events = []
          @connection.listen(@text_input, [
            [[P], ->(text_input, surface) { if surface.to_i == @handle.to_i; @connection.request(text_input, 1); @connection.request(text_input, 5, 0, 0); @connection.request(text_input, 7); end }],
            [[P], ->(text_input, _surface) { @connection.request(text_input, 2); @connection.request(text_input, 7); @composing = false }],
            [[P, I, I], ->(_text_input, text, start, finish) { value = text.null? ? "" : text.to_s.force_encoding("UTF-8"); @text_events << Input::Composition.new(value, [start, finish - start]); @composing = !value.empty? }],
            [[P], ->(_text_input, text) { @text_events << Input::TextInput.new(text.to_s.force_encoding("UTF-8")) unless text.null? }],
            [[U, U], ->(_text_input, before, after) { @delete_surrounding = [before, after] }],
            [[U], ->(_text_input, _serial) { @on_delete_surrounding&.call(*@delete_surrounding) if @delete_surrounding; @delete_surrounding = nil; @text_events.each { |event| input(event) }; @text_events.clear }]
          ])
        end
        def on_delete_surrounding(&block) = @on_delete_surrounding = block
        def surrounding_text(text, cursor:, anchor: cursor)
          return unless @text_input
          raise ArgumentError, "Wayland surrounding text is limited to 4000 bytes" if text.bytesize > 4000
          @connection.request(@text_input, 3, text, cursor, anchor)
          @connection.request(@text_input, 7)
        end
        def ime_state=(bounds)
          @ime_state = bounds
          return unless @text_input && bounds.is_a?(Bounds)
          @connection.request(@text_input, 6, bounds.x.to_i, bounds.y.to_i, bounds.width.ceil, bounds.height.ceil)
          @connection.request(@text_input, 7)
        end
        def setup_clipboard
          manager, seat = @globals.values_at("wl_data_device_manager", "wl_seat")
          return unless manager && seat
          @data_device = @connection.request(manager, 1, 0, seat, new_interface: "wl_data_device")
          @connection.listen(@data_device, [
            [[P], ->(_device, offer) { @offers[offer.to_i] = []; @connection.listen(offer, [[[P], ->(_offer, mime) { @offers[offer.to_i] << mime.to_s }], [[U], nil], [[U], ->(_offer, action) { @offer_actions[offer.to_i] = action }]]) }],
            [[U, P, I, I, P], ->(_device, serial, _surface, x, y, offer) { drag_enter(serial, x, y, offer) }],
            [[], ->(_device) { destroy_offer(@drag_offer) unless @pending_drop; @drag_offer = nil unless @pending_drop }],
            [[U, I, I], ->(_device, _time, x, y) { @drag_position = Point.new(x / 256.0, y / 256.0) }],
            [[], ->(_device) { @pending_drop = !!@drag_offer }],
            [[P], ->(_device, offer) { destroy_offer(@selection); @selection = offer.null? ? nil : offer }]
          ])
        end
        def write_clipboard(items)
          raise Error, "Wayland clipboard requires a focused input seat" unless @data_device && @serial.positive?
          unless items.is_a?(Array) && items.all? { |item| item.is_a?(Clipboard::Item) }
            raise TypeError, "clipboard items must be an Array of Clipboard::Item"
          end
          items.each do |item|
            item.formats.each_value { |data| raise Error, "Wayland selection exceeds 16 MiB" if data.bytesize > 16_777_216 }
          end
          super
          formats = items.each_with_object({}) { |item, result| item.formats.each { |mime, data| result[mime] ||= data } }
          source = @connection.request(@globals["wl_data_device_manager"], 0, 0, new_interface: "wl_data_source")
          @source_formats ||= {}
          @source_formats[source.to_i] = formats
          listen_clipboard_source(source)
          mimes = formats.keys
          mimes.concat(%w[text/plain;charset=utf-8 UTF8_STRING]) if formats.key?("text/plain")
          mimes.uniq.each { |mime| @connection.request(source, 0, mime) }
          @connection.request(@data_device, 1, source, @serial)
          @source = source
          items
        end
        def listen_clipboard_source(source)
          @connection.listen(source, [
            [[P], nil], [[P, I], ->(_source, mime, fd) {
              io = IO.for_fd(fd)
              begin
                formats = @source_formats[source.to_i] || {}
                data = formats[mime.to_s] || (formats["text/plain"] if %w[text/plain;charset=utf-8 UTF8_STRING].include?(mime.to_s))
                io.write(data) if data
              rescue Errno::EPIPE
              ensure
                io.close
              end
            }],
            [[], ->(_source) { @source_formats&.delete(source.to_i); @source = nil if @source == source; @connection.request(source, 1, destroy: true) }],
            [[], nil], [[], nil], [[U], nil]
          ])
        end
        def clipboard=(text)
          super
        end
        def clipboard = read_clipboard(types: ["text/plain"]).formats.fetch("text/plain", "")
        def clipboard_types
          return super if @source
          @offers.fetch(@selection&.to_i, []).filter_map do |mime|
            %w[text/plain;charset=utf-8 UTF8_STRING].include?(mime) ? "text/plain" : mime
          end.uniq.freeze
        end
        def read_clipboard(types:)
          raise TypeError, "clipboard types must be an Array" unless types.is_a?(Array)
          return super if @source
          offered = @offers.fetch(@selection&.to_i, [])
          formats = types.each_with_object({}) do |type, result|
            candidates = type == "text/plain" ? ["text/plain;charset=utf-8", "UTF8_STRING", "text/plain"] : [type]
            mime = candidates.find { |candidate| offered.include?(candidate) }
            result[type] = read_offer(@selection, [mime]) if mime
          end
          Clipboard::Content.new(formats)
        end
        def clipboard_paths
          Window.file_paths(read_selection(["text/uri-list"]))
        end
        def drag_enter(serial, x, y, offer)
          return if offer.null?
          @drag_offer, @drag_position = offer, Point.new(x / 256.0, y / 256.0)
          accept = @offers.fetch(offer.to_i, []).include?("text/uri-list")
          @connection.request(offer, 0, serial, accept ? "text/uri-list" : 0)
          @connection.request(offer, 4, accept ? 1 : 0, accept ? 1 : 0) if @connection.version(offer) >= 3
        end
        def finish_drop
          @pending_drop = false
          offer = @drag_offer
          accepted = @connection.version(offer) < 3 || @offer_actions[offer.to_i] == 1
          paths = accepted ? Window.file_paths(read_offer(offer, ["text/uri-list"])) : []
          @connection.request(offer, 3) if @connection.version(offer) >= 3 && !paths.empty?
          destroy_offer(offer)
          @drag_offer = nil
          input(Input::FileDrop.new(paths.freeze, @drag_position)) unless paths.empty?
        end
        def destroy_offer(offer)
          return unless offer
          @connection.request(offer, 2, destroy: true)
          @offers.delete(offer.to_i)
          @offer_actions.delete(offer.to_i)
        end
        def read_selection(types) = read_offer(@selection, types)
        def read_offer(offer, types)
          return "" unless offer
          mime = types.find { |type| @offers.fetch(offer.to_i, []).include?(type) }
          return "" unless mime
          reader, writer = IO.pipe
          @connection.request(offer, 1, mime, writer.fileno)
          @connection.library.fn(:wl_display_flush, [P], I).call(@connection.display)
          writer.close
          result, deadline = "".b, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
          loop do
            @connection.poll
            raise Error, "Wayland selection transfer timed out" unless IO.select([reader], nil, nil, [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max)
            data = reader.read_nonblock(65_536, exception: false)
            break if data.nil?
            result << data if data.is_a?(String)
            raise Error, "clipboard exceeds 16 MiB" if result.bytesize > 16_777_216
          end
          result
        ensure
          reader&.close
          writer&.close unless writer&.closed?
        end
        def cursor_style=(style)
          return unless @pointer_serial && @globals["wl_shm"]
          @cursors ||= FFI::Library.new("libwayland-cursor.so.0")
          @cursor_theme ||= @cursors.fn(:wl_cursor_theme_load, [P, I, P], P).call(0, 24, @globals["wl_shm"])
          name = {arrow: "left_ptr", text: "xterm", pointer: "hand2", crosshair: "crosshair", resize_horizontal: "sb_h_double_arrow", resize_vertical: "sb_v_double_arrow"}.fetch(style)
          cursor = @cursors.fn(:wl_cursor_theme_get_cursor, [P, P], P).call(@cursor_theme, name)
          return if cursor.null?
          images = cursor[8, 8].unpack1("J")
          image = Fiddle::Pointer.new(Fiddle::Pointer.new(images)[0, 8].unpack1("J"))
          _, _, hotspot_x, hotspot_y = image[0, 16].unpack("I4")
          buffer = @cursors.fn(:wl_cursor_image_get_buffer, [P], P).call(image)
          @cursor_surface ||= @connection.request(@globals["wl_compositor"], 0, 0, new_interface: "wl_surface")
          @connection.request(@pointer, 0, @pointer_serial, @cursor_surface, hotspot_x, hotspot_y)
          @connection.request(@cursor_surface, 1, buffer, 0, 0)
          @connection.request(@cursor_surface, 2, 0, 0, 0x7fffffff, 0x7fffffff)
          @connection.request(@cursor_surface, 6)
        end
        def prompt_for_paths(**options) = Linux::Window.instance_method(:prompt_for_paths).bind_call(self, **options)
        def open_url(url) = Linux::Window.instance_method(:open_url).bind_call(self, url)
        def toggle_fullscreen
          @fullscreen = !@fullscreen
          @fullscreen ? @connection.request(@toplevel, 11, 0) : @connection.request(@toplevel, 12)
          notify_state_change
        end
        def move_to_display(display)
          validate_display!(display)
          raise Error, "Wayland does not support arbitrary window positioning; use fullscreen_on"
        end
        # Wayland treats the output as a preference; the compositor decides whether to honor it.
        def fullscreen_on(display)
          validate_display!(display)
          output = @outputs[display.id]&.first
          raise Error, "display is no longer available" unless output

          @fullscreen = true
          @connection.request(@toplevel, 11, output)
          notify_state_change
          true
        end
        def close
          return false unless super
          Accessibility.close(self)
          close_appearance
          cleanup_native
          true
        end
        def cleanup_native
          @source_formats&.clear
          if @egl_display && !@egl_display.null?
            @egl.fn(:eglMakeCurrent, [P] * 4, U).call(@egl_display, 0, 0, 0)
            @egl.fn(:eglDestroySurface, [P, P], U).call(@egl_display, @egl_surface) if @egl_surface
            @egl.fn(:eglDestroyContext, [P, P], U).call(@egl_display, @egl_context) if @egl_context
            @egl.fn(:eglTerminate, [P], U).call(@egl_display)
          end
          @wayland_egl.fn(:wl_egl_window_destroy, [P], V).call(@egl_window) if @egl_window
          @cursors.fn(:wl_cursor_theme_destroy, [P], V).call(@cursor_theme) if @cursor_theme
          @xkb.fn(:xkb_state_unref, [P], V).call(@key_state) if @key_state
          @xkb.fn(:xkb_keymap_unref, [P], V).call(@keymap) if @keymap
          @xkb.fn(:xkb_context_unref, [P], V).call(@key_context) if @key_context
          @connection&.close
        end
      end
    end
  end
end
