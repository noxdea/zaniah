# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/linux"
require "zaniah/platform/linux/wayland_window"

class LinuxDragDropTest < Minitest::Test
  def test_x11_drag_selection_uses_drag_formats_not_clipboard_formats
    window = Zaniah::Platform::Linux::Window.allocate
    window.instance_variable_set(:@clipboard_formats, {"text/plain" => "📋"})
    names = []
    window.define_singleton_method(:atom) { |name| names << name; names.length }

    formats = {"text/plain" => "drag"}
    assert_equal "drag".b, window.own_selection("STRING", formats)
    window.own_selection("TARGETS", formats)
    assert_includes names, "STRING"
  end

  def test_x11_drag_completion_reports_target_action
    window = Zaniah::Platform::Linux::Window.allocate
    atoms = Hash.new { |hash, name| hash[name] = hash.length + 1 }
    window.define_singleton_method(:atom) { |name| atoms[name] }
    window.instance_variable_set(:@drag_data, Struct.new(:operations).new([:move, :copy]))
    window.instance_variable_set(:@outgoing_drag, {target: 42, accepted: false, operation: :move})
    completed = []
    window.define_singleton_method(:finish_outgoing_drag) { |action| completed << action }
    event = lambda do |name, data|
      bytes = "\0".b * 192
      bytes[40, 8] = [atoms[name]].pack("L!")
      bytes[56, 40] = data.pack("L!5")
      bytes
    end

    window.client_message(event.call("XdndStatus", [42, 1, 0, 0, atoms["XdndActionCopy"]]))
    assert window.instance_variable_get(:@outgoing_drag)[:accepted]
    assert_equal :copy, window.instance_variable_get(:@outgoing_drag)[:operation]
    window.client_message(event.call("XdndFinished", [42, 1, atoms["XdndActionCopy"], 0, 0]))
    assert_equal [:copy], completed
    window.client_message(event.call("XdndFinished", [42, 1, atoms["XdndActionLink"], 0, 0]))
    assert_equal [:copy, :none], completed
    window.instance_variable_get(:@outgoing_drag)[:target_version] = 4
    window.client_message(event.call("XdndStatus", [42, 1, 0, 0, atoms["XdndActionCopy"]]))
    window.client_message(event.call("XdndFinished", [42, 0, 0, 0, 0]))
    assert_equal [:copy, :none, :copy], completed
    assert_equal :move, window.xdnd_requested_action(1)
    assert_equal :copy, window.xdnd_requested_action(4)
    assert_equal :move, window.xdnd_requested_action(5)
  end

  def test_x11_drag_enter_uses_target_supported_version
    window = Zaniah::Platform::Linux::Window.allocate
    window.instance_variable_set(:@handle, 7)
    window.instance_variable_set(:@drag_data, Struct.new(:operations).new([:copy]))
    window.instance_variable_set(:@outgoing_drag, {target: nil, formats: {"text/plain" => "value"}, operation: :copy})
    window.define_singleton_method(:xdnd_target_at_pointer) { [42, 4] }
    atoms = Hash.new { |hash, name| hash[name] = hash.length + 1 }
    window.define_singleton_method(:atom) { |name| atoms[name] }
    messages = []
    window.define_singleton_method(:send_client_message) { |target, name, data| messages << [target, name, data] }
    event = "\0".b * 192
    window.outgoing_drag_pointer(event, 6)
    assert_equal 4, messages.first[2][1] >> 24
    assert_equal 4, window.instance_variable_get(:@outgoing_drag)[:target_version]
  end

  def test_x11_move_waits_for_delete_acknowledgement
    window = Zaniah::Platform::Linux::Window.allocate
    atoms = Hash.new { |hash, name| hash[name] = hash.length + 1 }
    window.define_singleton_method(:atom) { |name| atoms[name] }
    window.instance_variable_set(:@drag_source, 42)
    window.instance_variable_set(:@drag_accept, true)
    window.instance_variable_set(:@drop_targets, [])
    window.instance_variable_set(:@drop_formats, {"text/plain" => "drag"})
    window.instance_variable_set(:@drag_operation, :move)
    window.instance_variable_set(:@drag_position, Zaniah::Point.new(5, 5))
    requests, delivered, messages = [], [], []
    window.define_singleton_method(:x) { |*args| requests << args }
    window.define_singleton_method(:read_property) { |*_args| "".b }
    window.define_singleton_method(:deliver_drop) { |**args| delivered << args; :move }
    window.define_singleton_method(:send_client_message) { |*args| messages << args }

    window.finish_drop(0)
    assert_equal atoms["DELETE"], requests.first[5]
    assert_empty delivered
    window.finish_drop(atoms["ZANIAH_DROP_DELETE"])
    assert_equal :move, delivered.first[:operation]
    assert_equal atoms["XdndActionMove"], messages.first[2][2]
  end

  def test_wayland_drag_does_not_report_unselected_or_unsupported_action_as_copy
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    source = Fiddle::Pointer.malloc(1)
    events = nil
    connection = Object.new
    connection.define_singleton_method(:listen) { |_source, callbacks| events = callbacks }
    connection.define_singleton_method(:request) { |*_args, **_options| nil }
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@drag_source, source)
    window.instance_variable_set(:@drag_data, Struct.new(:operations).new([:move]))
    window.instance_variable_set(:@drag_action, :move)
    completed = []
    window.define_singleton_method(:finish_drag_source) { |action| completed << action }
    window.listen_clipboard_source(source)

    events[5][1].call(source, 0)
    assert_equal :none, window.instance_variable_get(:@drag_action)
    events[5][1].call(source, 1)
    assert_equal :none, window.instance_variable_get(:@drag_action)
    events[4][1].call(source)
    assert_equal [:none], completed
  end

  def test_wayland_offer_negotiates_matching_mime_and_action
    window = Zaniah::Platform::Linux::WaylandWindow.allocate
    offer = Fiddle::Pointer.malloc(1)
    requests = []
    connection = Object.new
    connection.define_singleton_method(:version) { |_offer| 3 }
    connection.define_singleton_method(:request) { |*args| requests << args }
    target = Object.new
    target.define_singleton_method(:drop_types) { ["image/png"] }
    region = Object.new
    region.define_singleton_method(:owner) { target }
    region.define_singleton_method(:contains?) { |_position| true }
    dispatcher = Object.new
    dispatcher.define_singleton_method(:hit_regions) { [region] }
    window.instance_variable_set(:@connection, connection)
    window.instance_variable_set(:@offers, {offer.to_i => ["image/png"]})
    window.instance_variable_set(:@offer_actions, {})
    window.instance_variable_set(:@offer_source_actions, {offer.to_i => 2})
    window.instance_variable_set(:@dispatcher, dispatcher)
    operation = :move
    window.define_singleton_method(:drag_over) { |**_options| operation }

    window.drag_enter(42, 256, 512, offer)
    assert_equal [offer, 0, 42, "image/png"], requests.fetch(0)
    assert_equal [offer, 4, 2, 2], requests.fetch(1)
    assert_equal :move, window.instance_variable_get(:@accepted_drag_operation)
    operation = :none
    window.update_drag_accept
    assert_equal [offer, 4, 0, 0], requests.last
  end
end
