# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/windows/drag_drop"

class WindowsDragDropTest < Minitest::Test
  DragDrop = Zaniah::Platform::Windows::DragDrop

  def test_formatetc_layout_and_interface_iids
    adapter = DragDrop.allocate
    bytes = adapter.format_descriptor(13)
    assert_equal 32, bytes.bytesize
    assert_equal [13, 0, 1, -1, 1], bytes.unpack("S< x6 Q< L< l< L< x4")

    owner = Object.new
    owner.define_singleton_method(:report) { |error| raise error }
    interface = DragDrop::Interface.new(owner, :target, [])
    output = [0].pack("J")
    assert_equal 0, interface.query_interface(Fiddle::Pointer[DragDrop::GUIDS.fetch(:target)], Fiddle::Pointer[output])
    assert_equal interface.pointer, output.unpack1("J")
    assert_equal DragDrop::E_NOINTERFACE, interface.query_interface(Fiddle::Pointer[DragDrop::GUIDS.fetch(:data)], Fiddle::Pointer[output])
    assert_equal 0, output.unpack1("J")
    assert_equal 0, Zaniah::FFI::COM.vcall(interface.pointer, 0, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT,
      Fiddle::Pointer[DragDrop::GUIDS.fetch(:target)], Fiddle::Pointer[output])
    assert_equal interface.pointer, output.unpack1("J")
  end

  def test_data_object_enumerates_offered_formats
    adapter = DragDrop.allocate
    adapter.define_singleton_method(:report) { |error| raise error }
    adapter.instance_variable_set(:@source_formats, {13 => "text", 15 => "files"})
    output = [0].pack("J")
    assert_equal 0, adapter.enumerate(1, Fiddle::Pointer[output])
    enumeration = output.unpack1("J")
    descriptors, fetched = "\0".b * 64, [0].pack("L<")
    assert_equal 0, Zaniah::FFI::COM.vcall(enumeration, 3,
      [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT,
      2, Fiddle::Pointer[descriptors], Fiddle::Pointer[fetched])
    assert_equal 2, fetched.unpack1("L<")
    assert_equal [13, 15], [descriptors[0, 2], descriptors[32, 2]].map { |bytes| bytes.unpack1("S<") }
    assert_equal 1, Zaniah::FFI::COM.vcall(enumeration, 3,
      [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT,
      1, Fiddle::Pointer[descriptors], Fiddle::Pointer[fetched])
  end
end
