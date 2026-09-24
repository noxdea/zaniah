# frozen_string_literal: true

require_relative "test_helper"

class TypedDragDropTest < Minitest::Test
  T = Zaniah

  def test_headless_drag_source_drop_and_legacy_file_event
    item = T::Clipboard::Item.new("text/plain" => "hello", "text/uri-list" => "file:///tmp/example%20file.txt\r\n")
    data = T::DragData.new(items: [item], operations: %i[copy move], on_move: -> {})
    events, drops = [], []
    window = T::Platform.open_window(width: 80, height: 40)
    window.on_input { |event| events << event }
    element = T::Div.new.w(80).h(40)
      .draggable { |_event, _cx| data }
      .on_drag_over { |drag, _cx| drag.accepts?("text/plain") ? :copy : :none }
      .on_drop(types: ["text/plain"]) { |drop, _cx| drops << drop }
    window.render(element)
    position = T::Point.new(10, 10)
    window.input(T::Input::MouseDown.new(position, :left, [], 1))
    assert_nil window.drag_data
    window.input(T::Input::MouseMove.new(T::Point.new(15, 10), []))
    assert_same data, window.drag_data
    assert_equal :copy, window.drag_over(types: data.types, position: position, operations: data.operations)
    assert_equal :none, window.drag_over(types: ["image/png"], position: position, operations: data.operations)
    assert_equal :copy, window.complete_drag(position: position)
    assert_nil window.drag_data
    assert_equal :copy, window.drag_result
    assert_equal [:begin, :complete], window.drag_history.map(&:first)
    assert_equal "hello", drops.fetch(0).content.fetch("text/plain")
    assert_equal :copy, drops.fetch(0).operation
    assert_equal ["/tmp/example file.txt"], events.grep(T::Input::FileDrop).fetch(0).paths
    assert_equal [T::Input::DataDrop, T::Input::FileDrop], events.last(2).map(&:class)
  ensure
    window&.close
  end

  def test_typed_drop_validation_and_unhandled_types
    item = T::Clipboard::Item.new("image/png" => "\x89PNG".b)
    data = T::DragData.new(items: [item])
    assert_equal ["image/png"], data.types
    assert_raises(TypeError) { T::DragData.new(items: ["bad"]) }
    assert_raises(ArgumentError) { T::DragData.new(items: [item], operations: [:invalid]) }
    assert_raises(ArgumentError) { T::DragData.new(items: [item], operations: [:move]) }
    window = T::Platform.open_window(width: 20, height: 20)
    called = false
    window.render(T::Div.new.w(20).h(20).on_drop(types: ["text/plain"]) { called = true })
    window.deliver_drop(content: data.content, position: T::Point.new(2, 2))
    refute called
    assert_raises(ArgumentError) { window.deliver_drop(content: data.content, position: T::Point.new(2, 2), operation: :none) }
    unsafe = T::Clipboard::Content.new("text/uri-list" => "file:///tmp/bad%00name\r\nfile://remote/tmp/file\r\n")
    assert_empty window.file_paths_in_drop(unsafe)
  ensure
    window&.close
  end

  def test_click_on_draggable_does_not_start_native_drag
    data = T::DragData.new(items: [T::Clipboard::Item.new("text/plain" => "value")])
    window = T::Platform.open_window(width: 30, height: 30)
    window.render(T::Div.new.w(30).h(30).draggable { data })
    point = T::Point.new(5, 5)
    window.input(T::Input::MouseDown.new(point, :left, [], 1))
    window.input(T::Input::MouseMove.new(T::Point.new(7, 6), []))
    window.input(T::Input::MouseUp.new(point, :left, []))
    assert_nil window.drag_data
    assert_empty window.drag_history
  ensure
    window&.close
  end

  def test_drag_over_alone_cannot_claim_successful_move
    moved = 0
    data = T::DragData.new(items: [T::Clipboard::Item.new("text/plain" => "value")], operations: [:move], on_move: -> { moved += 1 })
    window = T::Platform.open_window(width: 30, height: 30)
    window.render(T::Div.new.w(30).h(30).on_drag_over { |_event, _cx| :move })
    point = T::Point.new(5, 5)
    window.begin_drag(data)

    assert_equal :none, window.drag_over(types: data.types, position: point, operations: data.operations)
    assert_equal :none, window.complete_drag(position: point, operation: :move)
    assert_equal :none, window.drag_result
    assert_equal 0, moved
  ensure
    window&.close
  end

  def test_successful_move_commits_source_once
    moved = 0
    data = T::DragData.new(items: [T::Clipboard::Item.new("text/plain" => "value")], operations: [:move], on_move: -> { moved += 1 })
    window = T::Platform.open_window(width: 30, height: 30)
    window.render(T::Div.new.w(30).h(30).on_drop(types: ["text/plain"]) { |_drop, _cx| })
    point = T::Point.new(5, 5)
    window.begin_drag(data)
    assert window.commit_drag_move
    assert window.commit_drag_move
    assert_equal :move, window.complete_drag(position: point)
    assert_equal 1, moved
  ensure
    window&.close
  end

  def test_failed_move_callback_does_not_report_success
    data = T::DragData.new(items: [T::Clipboard::Item.new("text/plain" => "value")],
      operations: [:move], on_move: -> { raise "source was not removed" })
    window = T::Platform.open_window(width: 30, height: 30)
    window.render(T::Div.new.w(30).h(30).on_drop(types: ["text/plain"]) { |_drop, _cx| })
    window.begin_drag(data)
    assert_equal :none, window.complete_drag(position: T::Point.new(5, 5))
    assert_equal :none, window.drag_result
  ensure
    window&.close
  end
end
