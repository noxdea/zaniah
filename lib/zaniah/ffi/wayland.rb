# frozen_string_literal: true

require_relative "library"

module Zaniah
  module FFI
    # Runtime protocol metadata replaces generated C bindings. Core interfaces
    # are exported by libwayland-client; these extensions use protocol v1.
    class Wayland
      P, I, U, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOID
      PROTOCOLS = {
        "xdg_wm_base" => [[
          ["destroy", ""], ["create_positioner", "n", "xdg_positioner"],
          ["get_xdg_surface", "no", "xdg_surface", "wl_surface"], ["pong", "u"]
        ], [["ping", "u"]]],
        "xdg_positioner" => [[], []], "xdg_popup" => [[], []],
        "xdg_surface" => [[
          ["destroy", ""], ["get_toplevel", "n", "xdg_toplevel"],
          ["get_popup", "n?oo", "xdg_popup", "xdg_surface", "xdg_positioner"],
          ["set_window_geometry", "iiii"], ["ack_configure", "u"]
        ], [["configure", "u"]]],
        "xdg_toplevel" => [[
          ["destroy", ""], ["set_parent", "?o", "xdg_toplevel"], ["set_title", "s"], ["set_app_id", "s"],
          ["show_window_menu", "ouii", "wl_seat"], ["move", "ou", "wl_seat"], ["resize", "ouu", "wl_seat"],
          ["set_max_size", "ii"], ["set_min_size", "ii"], ["set_maximized", ""], ["unset_maximized", ""],
          ["set_fullscreen", "?o", "wl_output"], ["unset_fullscreen", ""], ["set_minimized", ""]
        ], [["configure", "iia"], ["close", ""]]],
        "zwp_text_input_manager_v3" => [[["destroy", ""], ["get_text_input", "no", "zwp_text_input_v3", "wl_seat"]], []],
        "zwp_text_input_v3" => [[
          ["destroy", ""], ["enable", ""], ["disable", ""], ["set_surrounding_text", "sii"],
          ["set_text_change_cause", "u"], ["set_content_type", "uu"], ["set_cursor_rectangle", "iiii"], ["commit", ""]
        ], [["enter", "o", "wl_surface"], ["leave", "o", "wl_surface"], ["preedit_string", "?sii"],
            ["commit_string", "?s"], ["delete_surrounding_text", "uu"], ["done", "u"]]],
        "zxdg_decoration_manager_v1" => [[["destroy", ""], ["get_toplevel_decoration", "no", "zxdg_toplevel_decoration_v1", "xdg_toplevel"]], []],
        "zxdg_toplevel_decoration_v1" => [[["destroy", ""], ["set_mode", "u"], ["unset_mode", ""]], [["configure", "u"]]],
        "zxdg_output_manager_v1" => [[["destroy", ""], ["get_xdg_output", "no", "zxdg_output_v1", "wl_output"]], []],
        "zxdg_output_v1" => [[["destroy", ""]], [["logical_position", "ii"], ["logical_size", "ii"], ["done", ""], ["name", "2s"], ["description", "2s"]]]
      }.freeze
      PROTOCOL_VERSIONS = {"zxdg_output_manager_v1" => 3, "zxdg_output_v1" => 3}.freeze
      attr_reader :library, :display

      def initialize
        @library = Library.new("libwayland-client.so.0")
        @interfaces, @keep, @listeners, @objects = {}, [], [], []
        PROTOCOLS.each_key { |name| @interfaces[name] = Fiddle::Pointer.malloc(40, Fiddle::RUBY_FREE) }
        PROTOCOLS.each do |name, (requests, events)|
          bytes = [keep_string(name), PROTOCOL_VERSIONS.fetch(name, 1), requests.length, messages(requests), events.length, messages(events)].pack("JiiJi x4J")
          @interfaces[name][0, 40] = bytes
        end
        @display = @library.fn(:wl_display_connect, [P], P).call(0)
        raise Zaniah::Error, "cannot connect to WAYLAND_DISPLAY" if @display.null?
      end
      def interface(name) = @interfaces[name] ||= Fiddle::Pointer.new(@library.handle["#{name}_interface"])
      def keep_string(text)
        string = text + "\0"
        @keep << string
        Fiddle::Pointer[string].to_i
      end
      def messages(definitions)
        return 0 if definitions.empty?
        data = definitions.map do |name, signature, *interfaces|
          count = signature.delete("?0123456789").length
          types = Array.new(count, 0)
          interfaces.each_with_index { |type, i| types[i] = interface(type).to_i if type }
          packed = types.pack("J*")
          @keep << packed
          [keep_string(name), keep_string(signature), Fiddle::Pointer[packed].to_i].pack("J3")
        end.join
        @keep << data
        Fiddle::Pointer[data].to_i
      end
      def version(proxy) = @library.fn(:wl_proxy_get_version, [P], U).call(proxy)
      def request(proxy, opcode, *arguments, new_interface: nil, version: nil, destroy: false)
        strings = []
        values = arguments.map do |value|
          if value.is_a?(String)
            strings << value + "\0"
            Fiddle::Pointer[strings.last].to_i
          else
            value.to_i & 0xffffffffffffffff
          end
        end.pack("Q*")
        object = @library.fn(:wl_proxy_marshal_array_flags, [P, U, P, U, U, P], P).call(proxy, opcode,
          new_interface ? interface(new_interface) : 0, version || self.version(proxy), destroy ? 1 : 0, values.empty? ? 0 : values)
        @objects << object if new_interface && !object.null?
        @objects.delete(proxy) if destroy
        object
      end
      def listen(proxy, events)
        @objects << proxy unless @objects.include?(proxy)
        callbacks = events.map do |types, block|
          Fiddle::Closure::BlockCaller.new(V, [P, P, *types]) do |_data, object, *arguments|
            begin
              block&.call(object, *arguments)
            rescue StandardError => error
              @error = error
            end
          end
        end
        table = callbacks.map(&:to_i).pack("J*")
        result = @library.fn(:wl_proxy_add_listener, [P, P, P], I).call(proxy, table, 0)
        raise Zaniah::Error, "Wayland listener registration failed" unless result.zero?
        @listeners << [table, callbacks]
      end
      def roundtrip
        result = @library.fn(:wl_display_roundtrip, [P], I).call(@display)
        raise @error if @error
        raise Zaniah::Error, "Wayland compositor disconnected" if result.negative?
      end
      def poll(timeout: 0)
        until @library.fn(:wl_display_prepare_read, [P], I).call(@display).zero?
          result = @library.fn(:wl_display_dispatch_pending, [P], I).call(@display)
          raise @error if @error
          raise Zaniah::Error, "Wayland compositor disconnected" if result.negative?
        end
        @library.fn(:wl_display_flush, [P], I).call(@display)
        fd = @library.fn(:wl_display_get_fd, [P], I).call(@display)
        ready = IO.select([IO.for_fd(fd, autoclose: false)], nil, nil, timeout)
        if ready
          result = @library.fn(:wl_display_read_events, [P], I).call(@display)
          raise Zaniah::Error, "Wayland compositor disconnected" if result.negative?
        else
          @library.fn(:wl_display_cancel_read, [P], V).call(@display)
        end
        @library.fn(:wl_display_dispatch_pending, [P], I).call(@display)
        raise @error if @error
      end
      def destroy(proxy)
        return unless proxy && !proxy.to_i.zero?
        @library.fn(:wl_proxy_destroy, [P], V).call(proxy)
        @objects.delete(proxy)
      end
      def close
        @objects.reverse_each { |object| @library.fn(:wl_proxy_destroy, [P], V).call(object) }
        @objects.clear
        @library.fn(:wl_display_disconnect, [P], V).call(@display)
      end
    end
  end
end
