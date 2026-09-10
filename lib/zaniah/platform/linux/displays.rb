# frozen_string_literal: true

require "fiddle/import"
require_relative "../../ffi/library"

module Zaniah
  module Platform
    module Linux
      module MonitorTypes
        extend Fiddle::Importer
        Monitor = struct ["unsigned long name", "int primary", "int automatic", "int output_count", "int x", "int y", "int width", "int height", "int mm_width", "int mm_height", "void *outputs"]
      end

      def self.displays(display_server: :auto)
        raise ArgumentError, "unknown Linux display server" unless [:auto, :x11, :wayland].include?(display_server)
        if display_server == :wayland || (display_server == :auto && ENV["WAYLAND_DISPLAY"])
          begin
            require_relative "wayland_display_discovery"
            return WaylandDisplayDiscovery.read
          rescue LoadError, Error
            raise if display_server == :wayland || !ENV["DISPLAY"]
          end
        end
        ptype, long, int = Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_INT
        library = FFI::Library.new("libX11.so.6")
        display = library.fn(:XOpenDisplay, [ptype], ptype).call(0)
        raise Error, "cannot open X display" if display.null?
        root = library.fn(:XDefaultRootWindow, [ptype], long).call(display)
        resources = library.fn(:XResourceManagerString, [ptype], ptype).call(display)
        scale = resources.null? ? 1.0 : (resources.to_s[/Xft\.dpi:\s*(\d+(?:\.\d+)?)/, 1]&.to_f || 96) / 96.0
        scale = scale.clamp(1.0, 4.0)
        begin
          randr = FFI::Library.new("libXrandr.so.2")
        rescue LoadError
          screen = library.fn(:XDefaultScreen, [ptype], int).call(display)
          width = library.fn(:XDisplayWidth, [ptype, int], int).call(display, screen)
          height = library.fn(:XDisplayHeight, [ptype, int], int).call(display, screen)
          return [Display.new(root, "X11 screen", Bounds.new(0, 0, width / scale, height / scale), scale, true)]
        end
        count = [0].pack("i")
        monitors = randr.fn(:XRRGetMonitors, [ptype, long, int, ptype], ptype).call(display, root, 1, count)
        Array.new(count.unpack1("i")) do |index|
          record = MonitorTypes::Monitor.new(monitors + index * MonitorTypes::Monitor.size)
          name = library.fn(:XGetAtomName, [ptype, long], ptype).call(display, record.name)
          text = name.null? ? "Display #{index}" : name.to_s.dup
          library.fn(:XFree, [ptype], int).call(name) unless name.null?
          Display.new(record.name, text, Bounds.new(record.x / scale, record.y / scale, record.width / scale, record.height / scale), scale, record.primary != 0)
        end
      ensure
        randr&.fn(:XRRFreeMonitors, [ptype], Fiddle::TYPE_VOID)&.call(monitors) if monitors && !monitors.null?
        library&.fn(:XCloseDisplay, [ptype], int)&.call(display) if display && !display.null?
      end
    end
  end
end
