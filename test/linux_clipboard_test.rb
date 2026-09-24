# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/linux"
require "zaniah/platform/linux/wayland_window"
require "weakref"

class LinuxClipboardTest < Minitest::Test
  def test_x11_advertises_mime_targets_and_streams_large_binary_selection
    skip "X11 is unavailable on Windows" if Gem.win_platform?
    window = Zaniah::Platform::Linux::Window.allocate
    atoms, changes = {}, []
    window.instance_variable_set(:@display, 1)
    window.instance_variable_set(:@handle, 2)
    window.define_singleton_method(:atom) { |name| atoms[name] ||= atoms.length + 10 }
    window.define_singleton_method(:atom_name) { |id| atoms.key(id) }
    window.define_singleton_method(:x) { |name, *| name == :XGetSelectionOwner ? 2 : 0 }
    window.define_singleton_method(:property) { |*args, **options| changes << [*args, options] }
    png = "\x89PNG".b + "a".b * 1_100_000
    window.write_clipboard([Zaniah::Clipboard::Item.new("text/plain" => "日本語", "image/png" => png)])

    assert_equal ["text/plain", "image/png"], window.clipboard_types
    assert_equal png, window.read_clipboard(types: ["image/png"]).fetch("image/png")
    request = "\0".b * 192
    request[40, 40] = [3, window.atom("CLIPBOARD"), window.atom("TARGETS"), window.atom("TEST"), 0].pack("L!5")
    window.selection_request(request)
    assert_equal 32, changes.last.last[:format]
    targets = changes.last[3].unpack("L!*").map { |id| atoms.key(id) }
    assert_includes targets, "image/png"
    assert_includes targets, "UTF8_STRING"

    changes.clear
    request[56, 8] = [window.atom("image/png")].pack("L!")
    window.selection_request(request)
    assert_equal window.atom("INCR"), changes.first[2]
    assert_equal png.bytesize, changes.first[3].unpack1("L!")
    while window.instance_variable_get(:@outgoing_incr)&.any?
      deleted = "\0".b * 192
      deleted[32, 8] = [3].pack("L!")
      deleted[40, 8] = [window.atom("TEST")].pack("L!")
      deleted[56, 4] = [1].pack("i")
      window.property_event(deleted)
    end
    chunks = changes.drop(1).map { |change| change[3] }
    assert_equal png, chunks.join.b
    assert_equal "", chunks.last
    assert chunks.all? { |chunk| chunk.bytesize <= 65_536 }
    assert_raises(Zaniah::Error) do
      window.write_clipboard([Zaniah::Clipboard::Item.new("image/png" => "x".b * (16_777_216 + 1))])
    end
  end

  def test_wayland_offers_all_mimes_and_preserves_binary_data
    skip "Wayland is unavailable on Windows" if Gem.win_platform?
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    calls, listeners = [], {}
    source = Fiddle::Pointer.new(7)
    connection = Object.new
    connection.define_singleton_method(:request) do |*args, **options|
      calls << [args, options]
      source if options[:new_interface] == "wl_data_source"
    end
    connection.define_singleton_method(:listen) { |object, events| listeners[object] = events }
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@data_device, Fiddle::Pointer.new(8))
    window.instance_variable_set(:@serial, 9)
    window.instance_variable_set(:@globals, {"wl_data_device_manager" => Fiddle::Pointer.new(10)})
    png = "\x89PNG\0\xff".b
    window.write_clipboard([Zaniah::Clipboard::Item.new("text/plain" => "日本語", "image/png" => png)])
    offered = calls.filter_map { |(args, _)| args[2] if args[0] == source && args[1] == 0 }
    assert_equal ["text/plain", "image/png", "text/plain;charset=utf-8", "UTF8_STRING"], offered

    reader, writer = IO.pipe
    listeners[source][1][1].call(source, Fiddle::Pointer["image/png"], writer.fileno)
    assert_equal png, reader.read.b
    assert_equal Encoding::BINARY, window.read_clipboard(types: ["image/png"]).fetch("image/png").encoding
  ensure
    reader&.close
  end

  def test_x11_reads_incremental_property_without_text_conversion
    skip "X11 is unavailable on Windows" if Gem.win_platform?
    window = Zaniah::Platform::Linux::Window.allocate
    window.instance_variable_set(:@display, 1)
    window.instance_variable_set(:@handle, 2)
    window.define_singleton_method(:atom) { |name| {"INCR" => 20, "image/png" => 21}.fetch(name) }
    expected = "\x89PNG".b + "a".b * 70_000
    replies = [[20, 32, [expected.bytesize].pack("L!")], [21, 8, expected], [21, 8, "".b]]
    pointers = []
    window.define_singleton_method(:x) do |name, _signature, _result, *args|
      next 0 unless name == :XGetWindowProperty
      type, format, value = replies.shift
      pointer = Fiddle::Pointer[value]
      pointers << pointer
      args[7][0, Fiddle::SIZEOF_LONG] = [type].pack("L!")
      args[8][0, 4] = [format].pack("i")
      args[9][0, Fiddle::SIZEOF_LONG] = [value.bytesize / (format == 32 ? Fiddle::SIZEOF_LONG : 1)].pack("L!")
      args[10][0, Fiddle::SIZEOF_LONG] = [0].pack("L!")
      args[11][0, Fiddle::SIZEOF_VOIDP] = [pointer.to_i].pack("J")
      0
    end
    changed = "\0".b * 192
    changed[32, 8] = [2].pack("L!")
    changed[40, 8] = [30].pack("L!")
    window.define_singleton_method(:poll_events) do
      property_event(changed) until replies.empty?
    end

    assert_equal expected, window.read_property(2, 30).b
    assert_empty replies
  end

  def test_x11_string_target_uses_latin1_in_both_directions
    skip "X11 is unavailable on Windows" if Gem.win_platform?
    window = Zaniah::Platform::Linux::Window.allocate
    atoms = {}
    window.instance_variable_set(:@display, 1)
    window.instance_variable_set(:@handle, 2)
    window.define_singleton_method(:atom) { |name| atoms[name] ||= atoms.length + 10 }
    window.define_singleton_method(:atom_name) { |id| atoms.key(id) }
    window.define_singleton_method(:x) { |name, *| name == :XGetSelectionOwner ? 2 : 0 }
    window.write_clipboard([Zaniah::Clipboard::Item.new("text/plain" => "café")])
    assert_equal "caf\xE9".b, window.own_selection("STRING")
    assert_includes window.own_selection("TARGETS").unpack("L!*").map { |id| atoms.key(id) }, "STRING"
    window.write_clipboard([Zaniah::Clipboard::Item.new("text/plain" => "日本語")])
    refute_includes window.own_selection("TARGETS").unpack("L!*").map { |id| atoms.key(id) }, "STRING"

    window.define_singleton_method(:owns_clipboard?) { false }
    window.define_singleton_method(:offered_clipboard_targets) { ["STRING"] }
    window.define_singleton_method(:selection) { |_| "caf\xE9".b }
    assert_equal "café", window.read_clipboard(types: ["text/plain"]).fetch("text/plain")
  end

  def test_x11_incr_subscriptions_are_counted_and_released_on_timeout_and_replacement
    skip "X11 is unavailable on Windows" if Gem.win_platform?
    window = Zaniah::Platform::Linux::Window.allocate
    atoms, selections = {}, []
    window.instance_variable_set(:@display, 1)
    window.instance_variable_set(:@handle, 2)
    window.define_singleton_method(:atom) { |name| atoms[name] ||= atoms.length + 10 }
    window.define_singleton_method(:atom_name) { |id| atoms.key(id) }
    window.define_singleton_method(:x) do |name, _signature, _result, *args|
      selections << [args[1], args[2]] if name == :XSelectInput
      name == :XGetSelectionOwner ? 2 : 0
    end
    window.define_singleton_method(:property) { |*| }
    item = Zaniah::Clipboard::Item.new("image/png" => "x".b * 70_000, "text/html" => "a" * 70_000)
    window.write_clipboard([item])
    ["image/png", "text/html"].each_with_index do |target, index|
      request = "\0".b * 192
      request[40, 40] = [3, window.atom("CLIPBOARD"), window.atom(target), window.atom("PROP#{index}"), 0].pack("L!5")
      window.selection_request(request)
    end
    assert_equal [[3, 1 << 22]], selections
    assert_equal 2, window.instance_variable_get(:@incr_subscriptions)[3]
    first = [3, window.atom("PROP0")]
    window.release_outgoing_incr(first)
    assert_equal 1, window.instance_variable_get(:@incr_subscriptions)[3]
    assert_equal [[3, 1 << 22]], selections
    window.expire_outgoing_incr(Float::INFINITY)
    assert_equal [[3, 1 << 22], [3, 0]], selections
    assert_empty window.instance_variable_get(:@outgoing_incr)

    request = "\0".b * 192
    request[40, 40] = [3, window.atom("CLIPBOARD"), window.atom("image/png"), window.atom("PROP2"), 0].pack("L!5")
    window.selection_request(request)
    window.write_clipboard([Zaniah::Clipboard::Item.new("text/plain" => "new")])
    assert_equal [[3, 1 << 22], [3, 0], [3, 1 << 22], [3, 0]], selections
    assert_empty window.instance_variable_get(:@outgoing_incr)
  end

  def test_wayland_cancelled_source_does_not_keep_old_blob_alive
    skip "Wayland is unavailable on Windows" if Gem.win_platform?
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    sources = [Fiddle::Pointer.new(41), Fiddle::Pointer.new(42)]
    listeners = {}
    connection = Object.new
    connection.define_singleton_method(:request) do |*_args, **options|
      sources.shift if options[:new_interface] == "wl_data_source"
    end
    connection.define_singleton_method(:listen) { |source, events| listeners[source] = events }
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@data_device, Fiddle::Pointer.new(8))
    window.instance_variable_set(:@serial, 9)
    window.instance_variable_set(:@globals, {"wl_data_device_manager" => Fiddle::Pointer.new(10)})
    old_source = sources.first
    weak = write_large_wayland_item(window)
    window.write_clipboard([Zaniah::Clipboard::Item.new("text/plain" => "new")])
    listeners[old_source][2][1].call(old_source)
    refute window.instance_variable_get(:@source_formats).key?(old_source.to_i)
    3.times { GC.start(full_mark: true, immediate_sweep: true) }
    refute weak.weakref_alive?
  end

  def test_wayland_external_offer_reads_binary_without_utf8_scrubbing
    skip "Wayland is unavailable on Windows" if Gem.win_platform?
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    bytes = "\x89PNG\0\xff".b
    writer_thread = nil
    connection = Object.new
    connection.define_singleton_method(:request) do |_offer, opcode, _mime, fd|
      next unless opcode == 1
      output = IO.for_fd(fd, autoclose: false).dup
      writer_thread = Thread.new { output.write(bytes); output.close }
    end
    library = Object.new
    library.define_singleton_method(:fn) { |*| ->(*) { 0 } }
    connection.define_singleton_method(:library) { library }
    connection.define_singleton_method(:display) { 1 }
    connection.define_singleton_method(:poll) { }
    offer = Fiddle::Pointer.new(11)
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@selection, offer)
    window.instance_variable_set(:@offers, {11 => ["image/png"]})

    content = window.read_clipboard(types: ["image/png", "text/html"])
    assert_equal ["image/png"], content.types
    assert_equal bytes, content.fetch("image/png")
    assert_equal Encoding::BINARY, content.fetch("image/png").encoding
  ensure
    writer_thread&.join
  end

  private

  def write_large_wayland_item(window)
    item = Zaniah::Clipboard::Item.new("image/png" => "x".b * 16_000_000)
    weak = WeakRef.new(item.fetch("image/png"))
    window.write_clipboard([item])
    weak
  end
end
