# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/linux"
require "zaniah/platform/linux/wayland_window"

class LinuxWindowStateTest < Minitest::Test
  def test_x11_frame_uses_root_coordinates_and_logical_pixels
    window = Zaniah::Platform::Linux::Window.allocate
    window.instance_variable_set(:@display, 1)
    window.instance_variable_set(:@handle, 2)
    window.instance_variable_set(:@root, 3)
    window.instance_variable_set(:@scale_factor, 2)
    window.define_singleton_method(:x) do |name, _types, _result, *args|
      case name
      when :XGetGeometry
        args[5][0, 4] = [800].pack("I")
        args[6][0, 4] = [600].pack("I")
      when :XTranslateCoordinates
        args[5][0, 4] = [20].pack("i")
        args[6][0, 4] = [30].pack("i")
      end
      1
    end
    assert_equal Zaniah::Bounds.new(10, 15, 400, 300), window.frame
  end

  def test_x11_wm_messages_and_drag_use_native_coordinates
    window = Zaniah::Platform::Linux::Window.allocate
    sent, calls, atoms = [], [], {}
    window.instance_variable_set(:@display, Fiddle::Pointer.new(1))
    window.instance_variable_set(:@handle, 2)
    window.instance_variable_set(:@root, 3)
    window.instance_variable_set(:@scale_factor, 1)
    window.instance_variable_set(:@content_size, Zaniah::Size.new(200, 100))
    window.instance_variable_set(:@decorations, :none)
    window.instance_variable_set(:@resizable, true)
    window.define_singleton_method(:atom) { |name| atoms[name] ||= atoms.length + 10 }
    window.define_singleton_method(:window_region_at) { |_| :drag }
    window.define_singleton_method(:input) { |event| calls << event }
    window.define_singleton_method(:x) do |name, _types, _result, *args|
      sent << [name, args]
      1
    end
    window.wm_state(1, "_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ")
    state = sent.find { |name, _| name == :XSendEvent }.last.last
    assert_equal [1, atoms["_NET_WM_STATE_MAXIMIZED_VERT"], atoms["_NET_WM_STATE_MAXIMIZED_HORZ"], 1, 0], state[56, 40].unpack("L!5")
    sent.clear
    window.wm_state(0, "_NET_WM_STATE_FULLSCREEN")
    state = sent.find { |name, _| name == :XSendEvent }.last.last
    assert_equal [0, atoms["_NET_WM_STATE_FULLSCREEN"], 0, 1, 0], state[56, 40].unpack("L!5")

    sent.clear
    event = "\0".b * 192
    event[64, 8] = [50, 10].pack("i2")
    event[72, 8] = [123, 234].pack("i2")
    event[80, 8] = [0, 1].pack("I2")
    window.mouse_event(event, 4)
    assert_includes sent.map(&:first), :XUngrabPointer
    moved = sent.find { |name, _| name == :XSendEvent }.last.last
    assert_equal [123, 234, 8, 1, 1], moved[56, 40].unpack("L!5")
    assert_empty calls
  end

  def test_x11_size_hints_pin_nonresizable_windows
    window = Zaniah::Platform::Linux::Window.allocate
    window.instance_variable_set(:@display, 1)
    window.instance_variable_set(:@handle, 2)
    window.instance_variable_set(:@scale_factor, 2)
    window.instance_variable_set(:@content_size, Zaniah::Size.new(200, 100))
    window.instance_variable_set(:@resizable, false)
    window.instance_variable_set(:@min_size, Zaniah::Size.new(100, 80))
    hints = nil
    window.define_singleton_method(:x) do |_name, _types, _result, *_args, given|
      hints = given
      1
    end
    window.configure_size_hints
    assert_equal (1 << 4) | (1 << 5), hints.flags
    assert_equal [400, 200, 400, 200], [hints.min_width, hints.min_height, hints.max_width, hints.max_height]
  end

  def test_wayland_frame_rejects_position_and_tracks_compositor_state
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    Zaniah::Platform::Headless::Window.instance_method(:initialize).bind_call(window, width: 200, height: 100)
    calls = []
    connection = Object.new
    connection.define_singleton_method(:request) { |*args| calls << args }
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@toplevel, Fiddle::Pointer.new(2))
    assert_equal Zaniah::Bounds.new(nil, nil, 200, 100), window.frame
    assert_raises(Zaniah::Error) { window.frame = Zaniah::Bounds.new(1, 2, 300, 150) }
    window.frame = Zaniah::Bounds.new(nil, nil, 300, 150)
    assert_equal Zaniah::Bounds.new(nil, nil, 300, 150), window.frame
    states = [1, 2].pack("L<*")
    descriptor = [states.bytesize, states.bytesize, Fiddle::Pointer[states].to_i].pack("J3")
    window.toplevel_configure(320, 180, Fiddle::Pointer[descriptor])
    assert window.maximized?
    assert window.fullscreen?
    assert_equal Zaniah::Bounds.new(nil, nil, 320, 180), window.state.frame
    assert_raises(Zaniah::Error) { window.always_on_top = true }
  ensure
    window&.device&.release
  end

  def test_wayland_drag_uses_input_serial_and_respects_controls
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    calls = []
    connection = Object.new
    connection.define_singleton_method(:request) { |*args| calls << args }
    seat, toplevel = Fiddle::Pointer.new(3), Fiddle::Pointer.new(4)
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@globals, {"wl_seat" => seat})
    window.instance_variable_set(:@toplevel, toplevel)
    window.instance_variable_set(:@serial, 42)
    window.instance_variable_set(:@position, Zaniah::Point.new(50, 20))
    window.instance_variable_set(:@content_size, Zaniah::Size.new(200, 100))
    window.instance_variable_set(:@resizable, true)
    window.define_singleton_method(:window_region_at) { |_| :drag }
    assert window.native_window_drag
    assert_equal [toplevel, 5, seat, 42], calls.pop
    window.instance_variable_set(:@position, Zaniah::Point.new(1, 1))
    assert window.native_window_drag
    assert_equal [toplevel, 6, seat, 42, 5], calls.pop
    window.define_singleton_method(:window_region_at) { |_| :close }
    refute window.native_window_drag
    assert_empty calls
  end

  def test_wayland_minimization_does_not_pretend_to_be_reversible
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    Zaniah::Platform::Headless::Window.instance_method(:initialize).bind_call(window)
    calls = []
    connection = Object.new
    connection.define_singleton_method(:request) { |*args| calls << args }
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@toplevel, Fiddle::Pointer.new(4))
    window.minimize
    assert window.minimized?
    assert_equal 13, calls.last[1]
    assert_raises(Zaniah::Error) { window.restore }
  ensure
    window&.device&.release
  end
end
