# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"

backend = RUBY_PLATFORM.include?("darwin") ? :mac : :linux
window = Zaniah::Platform.open_window(backend: backend, width: 320, height: 180, title: "Native file drop check")
events = []
window.on_input { |event| events << event }
expected = "/tmp/zaniah 日本.txt"
if backend == :mac
  objc = Zaniah::FFI::ObjC
  board = objc.send(objc.klass("NSPasteboard"), "pasteboardWithUniqueName")
  objc.send(board, "setString:forType:", objc.string("file:///tmp/zaniah%20%E6%97%A5%E6%9C%AC.txt"), objc.string("public.file-url"), args: [:pointer, :pointer], result: :bool)
  objc.subclass("ZaniahDropFixture", "NSObject") do |klass|
    objc.method(klass, "draggingPasteboard", result: :pointer, encoding: "@@:") { board }
    objc.method(klass, "draggingLocation", result: :point, encoding: "{CGPoint=dd}@:") { [40.0, 40.0] }
  end
  dragging = objc.new("ZaniahDropFixture")
  accepted = objc.send(window.view, "performDragOperation:", dragging, args: [:pointer], result: :bool)
  raise "Cocoa rejected file drop" if accepted.zero?
  window.tooltip = "Native tooltip"
  raise "tooltip not installed" unless objc.text(objc.send(window.view, "toolTip")) == "Native tooltip"
  changes = []
  window.on_appearance { |value| changes << value }
  %w[NSAppearanceNameDarkAqua NSAppearanceNameAqua].each do |name|
    # Exported symbol names are not their string values (DarkAqua/Aqua).
    native = objc.send(objc.klass("NSAppearance"), "appearanceNamed:", objc.string(name.delete_prefix("NSAppearanceName")), args: [:pointer])
    objc.send(window.view, "setAppearance:", native, args: [:pointer], result: :void)
    window.tick
  end
  raise "appearance notification missing: #{changes.inspect}" unless changes.include?(:dark) && changes.include?(:light)
  objc.send(window.view, "setAppearance:", 0, args: [:pointer], result: :void)
  objc.release(dragging)
  objc.send(board, "releaseGlobally", result: :void)
else
  raise "run this protocol check under X11" unless window.is_a?(Zaniah::Platform::Linux::Window)
  klass = Zaniah::Platform::Linux::Window
  ptype, long, int = klass::P, klass::L, klass::I
  source = klass.allocate
  source.instance_variable_set(:@x, Zaniah::FFI::Library.new("libX11.so.6"))
  source.instance_variable_set(:@atoms, {})
  display = source.x(:XOpenDisplay, [ptype], ptype, 0)
  source.instance_variable_set(:@display, display)
  root = source.x(:XDefaultRootWindow, [ptype], long, display)
  handle = source.x(:XCreateSimpleWindow, [ptype, long, int, int, int, int, int, long, long], long, display, root, 0, 0, 40, 40, 0, 0, 0)
  source.instance_variable_set(:@handle, handle)
  source.x(:XSetSelectionOwner, [ptype, long, long, long], int, display, source.atom("XdndSelection"), handle, 0)
  source.send_client_message(window.handle, "XdndEnter", [handle, 5 << 24, source.atom("text/uri-list"), 0, 0])
  source.send_client_message(window.handle, "XdndPosition", [handle, 0, (20 << 16) | 30, 0, source.atom("XdndActionCopy")])
  source.send_client_message(window.handle, "XdndDrop", [handle, 0, 0, 0, 0])
  finished, deadline = false, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  until finished || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    window.tick
    while source.x(:XPending, [ptype], int, display).positive?
      event = "\0".b * 192
      source.x(:XNextEvent, [ptype, ptype], int, display, event)
      if event.unpack1("i") == 30
        requestor, selection, target, property, time = event[40, 40].unpack("L!5")
        warn "XDND request #{[requestor, selection, target, property, time].inspect}; target=#{window.handle}, source=#{handle}" if ENV["ZANIAH_DROP_DEBUG"]
        source.property(requestor, property, target, "# file offer\r\nfile:///tmp/zaniah%20%E6%97%A5%E6%9C%AC.txt\r\n")
        reply = "\0".b * 192
        reply[0, 4] = [31].pack("i")
        reply[24, 8] = [display.to_i].pack("J")
        reply[32, 40] = [requestor, selection, target, property, time].pack("L!5")
        source.x(:XSendEvent, [ptype, long, int, long, ptype], int, display, requestor, 0, 0, reply)
        source.x(:XFlush, [ptype], int, display)
      elsif event.unpack1("i") == 33 && event[40, 8].unpack1("L!") == source.atom("XdndFinished")
        raise "XDND source did not receive success" unless event[64, 8].unpack1("L!") == 1
        finished = true
      end
    end
    sleep 0.005 unless finished
  end
  raise "XDND handshake timed out" unless finished
  source.x(:XDestroyWindow, [ptype, long], int, display, handle)
  source.x(:XCloseDisplay, [ptype], int, display)
end
drop = events.find { |event| event.is_a?(Zaniah::Input::FileDrop) }
raise "file drop missing or corrupted: #{events.inspect}" unless drop&.paths == [expected]
puts "#{window.class}: #{drop.inspect}"
window.close
