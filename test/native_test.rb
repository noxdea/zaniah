# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ffi/library"
require "zaniah/ffi/com"
require "zaniah/gpu/instance_packing"
require "rbconfig"

class NativeTest < Minitest::Test
  def test_library_signatures_are_cached_separately
    library = Zaniah::FFI::Library.new(RUBY_PLATFORM.match?(/mingw|mswin/) ? "msvcrt.dll" : nil)
    args = [Fiddle::TYPE_VOIDP]
    assert_same library.fn(:strlen, args, Fiddle::TYPE_SIZE_T), library.fn(:strlen, args, Fiddle::TYPE_SIZE_T)
    assert_equal 3, library.fn(:strlen, args, Fiddle::TYPE_SIZE_T).call("abc")
    refute_same library.fn(:strlen, args, Fiddle::TYPE_SIZE_T), library.fn(:strlen, args, Fiddle::TYPE_INT)
  end

  def test_com_vtable_call
    closure = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT]) { |_, value| value + 7 }
    table = [closure.to_i].pack("J")
    object = [Fiddle::Pointer[table].to_i].pack("J")
    assert_equal 12, Zaniah::FFI::COM.vcall(Fiddle::Pointer[object], 0, [Fiddle::TYPE_INT], Fiddle::TYPE_INT, 5)
  end

  def test_instances_preserve_transparency_order_and_clip
    scene = Zaniah::Scene.new
    texture = Zaniah::GPU::Texture.new(2, 2, format: :r8)
    scene.quad(0, 0, 10, 10, color: "#fff")
    scene.quad(0, 0, 10, 10, color: "#f005")
    scene.sprite(0, 0, 2, 2, texture: texture)
    clip = Zaniah::Bounds.new(1, 1, 2, 2)
    scene.clip(clip) { scene.quad(0, 0, 10, 10, color: "#0f0") }
    bytes, batches = Zaniah::GPU::InstancePacking.pack(scene)
    assert_equal 4 * 40 * 4, bytes.bytesize
    assert_equal [2, 1, 1], batches.map(&:last)
    assert_equal [:quad, :sprite, :quad], batches.map { |batch| batch[0][0] }
    assert_equal clip, batches.last[0][2]
    assert_equal 1, bytes.unpack("f*")[2 * 40 + 31]
  end

  def test_objc_aggregate_call_and_callback
    skip "Objective-C runtime is macOS only" unless RUBY_PLATFORM.include?("darwin")
    require "zaniah/ffi/objc"
    foundation = Zaniah::FFI::Library.new("/System/Library/Frameworks/Foundation.framework/Foundation")
    objc = Zaniah::FFI::ObjC
    assert_equal "日本語", objc.text(objc.string("日本語"))
    rect = [1.0, 2.0, 30.0, 40.0]
    object = objc.send(objc.klass("NSValue"), "valueWithRect:", rect, args: [:rect])
    assert_equal rect, objc.send(object, "rectValue", result: :rect)
    klass = objc.subclass("ZaniahAggregateTest", "NSObject") do |native_class|
      objc.method(native_class, "rangeByAdding:", args: [:range], result: :range, encoding: "{_NSRange=QQ}@:{_NSRange=QQ}") { |_, _, range| range.map { |n| n + 2 } }
    end
    object = objc.send(objc.send(klass, "alloc"), "init")
    assert_equal [5, 8], objc.send(object, "rangeByAdding:", [3, 6], args: [:range], result: :range)
    objc.release(object)
    refute_nil foundation
  end

  def test_native_structure_layouts_and_windows_unicode_helpers
    require "zaniah/platform/windows"
    unless Gem.win_platform?
      require "zaniah/platform/linux"
      assert_equal 64, Zaniah::Platform::Linux::Types::Visual.size
      assert_equal 112, Zaniah::Platform::Linux::Types::Attributes.size
      assert_equal 56, Zaniah::Platform::Linux::MonitorTypes::Monitor.size
    end
    assert_equal 80, Zaniah::Platform::Windows::Types::WindowClass.size
    assert_equal 40, Zaniah::Platform::Windows::Types::PixelFormat.size
    assert_equal 152, Zaniah::Platform::Windows::Types::OpenFileName.size
    window = Zaniah::Platform::Windows::Window.allocate
    assert_equal(-1, window.signed16(0xffff))
    assert_equal(-32768, window.signed16(0x8000))
    assert_equal 32767, window.signed16(0x7fff)
    assert_equal "日本語\0".encode("UTF-16LE").b, window.wide("日本語")
  end

  def test_objc_scalar_fast_path_preserves_types_nil_and_reentrant_callbacks
    skip "Objective-C runtime is macOS only" unless RUBY_PLATFORM.include?("darwin")
    require "zaniah/ffi/objc"
    Zaniah::FFI::Library.new("/System/Library/Frameworks/Foundation.framework/Foundation")
    objc = Zaniah::FFI::ObjC
    number = objc.klass("NSNumber")
    unsigned = objc.send(number, "numberWithUnsignedLongLong:", 2**64 - 1, args: [:ulong])
    assert_equal 2**64 - 1, objc.send(unsigned, "unsignedLongLongValue", result: :ulong)
    signed = objc.send(number, "numberWithLongLong:", -123, args: [:long])
    assert_equal(-123, objc.send(signed, "longLongValue", result: :long))
    floating = objc.send(number, "numberWithFloat:", -1.25, args: [:float])
    assert_in_delta(-1.25, objc.send(floating, "doubleValue", result: :double), 0.0001)
    assert_equal 0, objc.send(0, "length", result: :ulong)
    klass = objc.subclass("ZaniahScalarTest", "NSObject") do |native_class|
      objc.method(native_class, "sum:flag:", args: [:long, :bool], result: :long, encoding: "q@:qB") do |_, _, value, flag|
        value + flag + objc.send(objc.string("abc"), "length", result: :ulong)
      end
    end
    object = objc.send(objc.send(klass, "alloc"), "init")
    assert_equal(-2, objc.send(object, "sum:flag:", -5, 0, args: [:long, :bool], result: :long))
    assert_equal 9, objc.send(object, "sum:flag:", 5, 1, args: [:long, :bool], result: :long)
    assert_raises(ArgumentError) { objc.send(object, "sum:flag:", 1, args: [:long, :bool], result: :long) }
    objc.release(object)
  end

  def test_windows_command_arguments_and_terminal_size
    require "zaniah/platform/windows/terminal"
    terminal = Zaniah::Platform::Windows::Terminal
    assert_equal '""', terminal.quote_argument("")
    assert_equal "ruby", terminal.quote_argument("ruby")
    assert_equal '"a b"', terminal.quote_argument("a b")
    assert_equal '"a\\"b"', terminal.quote_argument('a"b')
    assert_equal '"a b\\\\"', terminal.quote_argument("a b\\")
    assert_equal 80 | (24 << 16), terminal.allocate.coordinate(80, 24)
    assert_raises(ArgumentError) { terminal.allocate.coordinate(0, 24) }
  end

  def test_windows_terminal_keeps_pseudoconsole_pipes_until_process_creation
    skip "Windows only" unless RUBY_PLATFORM.match?(/mingw|mswin/)
    require "zaniah/platform/windows/terminal"
    terminal = Zaniah::Platform::Windows::Terminal.new(command: [RbConfig.ruby, "-e", 'STDOUT.binmode; STDOUT.write("ready")'])
    output = +""
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until output.include?("ready")
      chunk = terminal.read_available
      break if chunk.nil?
      output << chunk
      raise "terminal output timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01 if chunk.empty?
    end
    assert_includes output, "ready"
  ensure
    terminal&.close
  end

  def test_system_font_raster_provider
    skip "native font oracle is macOS/Linux only" if RUBY_PLATFORM.match?(/mingw|mswin/)
    require "alhena"
    font = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
    if RUBY_PLATFORM.include?("darwin")
      require "zaniah/platform/mac/core_text"
      provider = Zaniah::Platform::Mac::CoreText.new
    else
      require "zaniah/platform/linux/free_type"
      provider = Zaniah::Platform::Linux::FreeType.new
    end
    glyph = font.glyph_id("A")
    assert_kind_of String, provider.cache_key
    assert_same provider.cache_key, provider.cache_key
    refute_empty provider.cache_key
    bitmap = provider.rasterize(font, glyph, size: 32)
    assert_equal [15, 23, 0, 23], [bitmap.width, bitmap.height, bitmap.left, bitmap.top]
    assert_equal bitmap.width * bitmap.height, bitmap.coverage.bytesize
    assert bitmap.coverage.bytes.any? { |value| value > 0 && value < 255 }
    shifted = provider.rasterize(font, glyph, size: 32, subpixel_x: 0.25)
    refute_equal bitmap.coverage, shifted.coverage
    assert_raises(ArgumentError) { provider.rasterize(font, glyph, size: 0) }
  ensure
    provider&.close
  end

  def test_vulkan_rejects_invalid_dimensions_and_shader_bytes
    require "zaniah/gpu/vulkan"
    assert_raises(ArgumentError) { Zaniah::GPU::Vulkan.new(width: 0, height: 10) }
    renderer = Zaniah::GPU::Vulkan.allocate
    assert_raises(ArgumentError) { renderer.shader("invalid") }
    assert_raises(ArgumentError) { renderer.shader("\0" * 20) }
    assert_raises(ArgumentError) { renderer.shader([0x07230203].pack("V") + "\0" * 17) }
  end

  def test_native_file_uris_and_xim_preedit_replacements
    require "zaniah/platform/linux"
    klass = Zaniah::Platform::Linux::Window
    uris = "# comment\r\nfile:///tmp/a%20b.txt\r\nfile://localhost/tmp/%E6%97%A5.txt\nfile://otherhost/private\nhttps://example.com/no\nfile:///bad%00path\n"
    assert_equal ["/tmp/a b.txt", "/tmp/日.txt"], klass.file_paths(uris)
    window = klass.allocate
    events = []
    window.define_singleton_method(:input) { |event| events << event }
    window.instance_variable_set(:@preedit, "にほん")
    text = "日本".codepoints.pack("I*")
    descriptor = [2, 0, 1, Fiddle::Pointer[text].to_i].pack("Sx6Ji x4J")
    change = [2, 0, 3, Fiddle::Pointer[descriptor].to_i].pack("i3x4J")
    window.preedit_draw(Fiddle::Pointer[change])
    assert_equal "日本", events.last.text
    assert_equal [2, 0], events.last.selection
  end

  def test_linux_appearance_monitor_handles_fragmented_signals
    require "zaniah/platform/linux/appearance_aware"
    window = Object.new.extend(Zaniah::Platform::Linux::AppearanceAware)
    window.define_singleton_method(:request_frame) { }
    reader, writer = IO.pipe
    changes = []
    window.instance_variable_set(:@appearance_io, reader)
    window.instance_variable_set(:@appearance_buffer, +"")
    window.instance_variable_set(:@on_appearance, ->(value) { changes << value })
    writer.write("org.freedesktop.portal.Settings.SettingChanged ('org.freedesktop.appearance', 'color-")
    window.poll_appearance
    assert_empty changes
    writer.write("scheme', <uint32 1>)\n")
    window.poll_appearance
    assert_equal [:dark], changes
  ensure
    writer&.close
    window&.close_appearance
  end

  def test_wayland_drop_requires_negotiated_copy_action
    require "zaniah/platform/linux"
    require "zaniah/platform/linux/wayland_window"
    calls = []
    connection = Object.new
    connection.define_singleton_method(:version) { |_| 3 }
    connection.define_singleton_method(:request) { |*args, **options| calls << [args, options] }
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@offers, {7 => ["text/uri-list"]})
    window.instance_variable_set(:@offer_actions, {7 => 1})
    events = []
    window.define_singleton_method(:input) { |event| events << event }
    window.define_singleton_method(:read_offer) { |*| "file:///tmp/drop.txt\n" }
    window.drag_enter(10, 20 * 256, 30 * 256, Fiddle::Pointer.new(7))
    window.finish_drop
    assert_equal ["/tmp/drop.txt"], events.last.paths
    assert_equal Zaniah::Point.new(20, 30), events.last.position
    assert calls.any? { |(args, _)| args[1] == 3 }, "successful drop must finish"
    assert calls.last[1][:destroy], "offer must be destroyed after finish"
    calls.clear
    window.instance_variable_set(:@offers, {7 => ["text/uri-list"]})
    window.instance_variable_set(:@offer_actions, {7 => 0})
    window.drag_enter(11, 0, 0, Fiddle::Pointer.new(7))
    window.finish_drop
    assert_equal 1, events.length
    refute calls.any? { |(args, _)| args[1] == 3 }, "unnegotiated drop must not finish"
  end

  def test_wayland_uses_only_entered_monitor_scales
    require "zaniah/platform/linux"
    require "zaniah/platform/linux/wayland_window"
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    connection = Object.new
    connection.define_singleton_method(:request) { |*| }
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@handle, 1)
    window.instance_variable_set(:@scale_factor, 1)
    window.instance_variable_set(:@content_size, Zaniah::Size.new(800, 600))
    window.instance_variable_set(:@outputs, {10 => [10, 1], 20 => [20, 2]})
    window.instance_variable_set(:@entered_outputs, [10])
    window.define_singleton_method(:resize) { |*| }
    window.output_scale
    assert_equal 1, window.scale_factor
    window.instance_variable_set(:@entered_outputs, [10, 20])
    window.output_scale
    assert_equal 2, window.scale_factor
    window.instance_variable_set(:@entered_outputs, [10])
    window.output_scale
    assert_equal 1, window.scale_factor
  end
end
