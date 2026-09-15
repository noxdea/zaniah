# frozen_string_literal: true

require_relative "test_helper"

class DragDropTest < Minitest::Test
  T = Zaniah
  D = Zaniah::DragDrop

  def setup
    @app = T::App.new
    @window = @app.open_window(width: 120, height: 40)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_pointer_drag_obeys_threshold_and_emits_target_transitions
    events = []
    reorder = D::Reorder.new(threshold: 5, locate: lambda { |point, _source|
      point.x < 60 ? D::Target.new(:left, :before) : D::Target.new(:right, :after)
    }).on_event { |event| events << [event.phase, event.target&.id] }
    source = T::Div.new.w(120).h(40)
      .on_mouse_down { |event, _| reorder.press(:source, event.position) }
      .on_drag { |event, _| reorder.move(event.position) }
      .on_mouse_up { |event, _| reorder.release(event.position) }
    @window.draw { source }
    @window.tick

    @window.input(T::Input::MouseDown.new(T::Point.new(1, 1), :left, [], 1))
    @window.input(T::Input::MouseMove.new(T::Point.new(3, 1), []))
    refute reorder.dragging?
    @window.input(T::Input::MouseMove.new(T::Point.new(20, 1), []))
    @window.input(T::Input::MouseMove.new(T::Point.new(21, 1), []))
    @window.input(T::Input::MouseMove.new(T::Point.new(80, 1), []))
    @window.input(T::Input::MouseUp.new(T::Point.new(81, 1), :left, []))

    assert_equal [[:press, nil], [:start, nil], [:enter, :left], [:over, :left],
      [:leave, :left], [:enter, :right], [:over, :right], [:drop, :right]], events
    assert_equal "Moved source after right", reorder.announcement
    refute reorder.dragging?
    assert_nil reorder.source_id
  end

  def test_release_before_threshold_is_not_a_drop
    drops = []
    reorder = D::Reorder.new(threshold: 5,
      locate: ->(_point, _source) { D::Target.new(:target, :before) }).on_drop { |event| drops << event }

    reorder.press(:source, T::Point.new(0, 0))

    refute reorder.release(T::Point.new(2, 2))
    assert_empty drops
    assert_nil reorder.source_id
  end

  def test_threshold_uses_distance_with_negative_coordinates
    reorder = D::Reorder.new(threshold: 5,
      locate: ->(*) { D::Target.new(:target, :before) })
    reorder.press(:source, T::Point.new(-3, -4))

    refute reorder.move(T::Point.new(0, -4))
    assert reorder.move(T::Point.new(0, 0))
    assert reorder.dragging?
    assert_raises(ArgumentError) { D::Reorder.new(threshold: -1, locate: ->(*) {}) }
  end

  def test_target_and_source_removal_leave_controller_reusable
    phases = []
    reorder = D::Reorder.new(threshold: 0,
      locate: ->(_point, _source) { D::Target.new(:target, :inside) })
      .on_event { |event| phases << [event.phase, event.reason] }

    reorder.press(:source, T::Point.new(0, 0))
    reorder.move(T::Point.new(0, 0))
    assert reorder.remove(:target)
    assert reorder.dragging?
    assert_nil reorder.target
    assert reorder.remove(:source)
    refute reorder.dragging?

    reorder.press(:again, T::Point.new(0, 0))
    assert_equal :again, reorder.source_id
    assert_includes phases, [:leave, :removed]
    assert_includes phases, [:cancel, :removed]
  end

  def test_callback_error_cancels_state_and_preserves_original_error
    events = []
    reorder = D::Reorder.new(threshold: 0, locate: ->(*) { raise "locator failed" })
      .on_event { |event| events << event.phase }
    reorder.press(:source, T::Point.new(0, 0))

    error = assert_raises(RuntimeError) { reorder.move(T::Point.new(1, 0)) }

    assert_equal "locator failed", error.message
    assert_equal %i[press start cancel], events
    refute reorder.dragging?
    assert_nil reorder.source_id
  end

  def test_callback_reentry_is_rejected_without_leaving_stale_state
    events = []
    reorder = nil
    reorder = D::Reorder.new(threshold: 0,
      locate: ->(*) { D::Target.new(:target, :after) }).on_event do |event|
      events << event.phase
      reorder.cancel if event.phase == :start
    end
    reorder.press(:source, T::Point.new(-3, -4))

    error = assert_raises(T::Error) { reorder.move(T::Point.new(0, 0)) }

    assert_match(/must not re-enter/, error.message)
    assert_equal %i[press start cancel], events
    assert_nil reorder.source_id
    assert_nil reorder.target
    refute reorder.dragging?
  end

  def test_drop_callback_error_also_resets_state
    reorder = D::Reorder.new(threshold: 0,
      locate: ->(*) { D::Target.new(:target, :after) }).on_drop { raise "drop failed" }
    reorder.press(:source, T::Point.new(0, 0))
    reorder.move(T::Point.new(1, 0))

    assert_raises(RuntimeError) { reorder.release }
    assert_nil reorder.source_id
    refute reorder.dragging?
  end

  def test_drop_callback_error_does_not_emit_cancel_after_drop
    phases = []
    reorder = D::Reorder.new(threshold: 5,
      locate: ->(*) { D::Target.new(:target, :after) })
      .on_event { |event| phases << event.phase }
      .on_drop { raise "drop failed" }
    reorder.press(:source, T::Point.new(-3, -4))
    reorder.move(T::Point.new(0, 0))

    assert_raises(RuntimeError) { reorder.release }
    assert_equal %i[press start enter drop], phases
    assert_nil reorder.source_id
    refute reorder.dragging?
  end

  def test_keyboard_reorder_uses_stable_ids_and_publishes_live_status
    items = [{id: :alpha, label: "Alpha"}, {id: :beta, label: "Beta"}, {id: :gamma, label: "Gamma"}]
    reads, announcements = 0, []
    reorder = D::Reorder.new(locate: ->(*) {}, label: ->(id) { id.to_s.capitalize },
      keyboard: lambda { |id, direction|
        reads += 1
        index = items.index { |item| item[:id] == id }
        target = direction == :previous ? index - 1 : index + 1
        target.between?(0, items.length - 1) ? D::Target.new(items[target][:id], direction == :previous ? :before : :after) : nil
      }).on_drop do |event|
        source = items.index { |item| item[:id] == event.source_id }
        item = items.delete_at(source)
        target = items.index { |candidate| candidate[:id] == event.target.id }
        target += 1 if event.target.position == :after
        items.insert(target, item)
      end.on_announce { |message| announcements << message }

    assert reorder.action(:beta, :reorder_before)
    assert_equal %i[beta alpha gamma], items.map { |item| item[:id] }
    assert_equal 1, reads
    assert_equal "Moved Beta before Alpha", reorder.announcement
    assert_equal [reorder.announcement], announcements

    tree = T::Accessibility::Tree.new
    assert tree.update(reorder, nil)
    assert_equal :status, tree.root.role
    assert_equal true, tree.root.states[:live]
    first_revision = tree.root.states[:revision]

    assert reorder.keyboard(:beta, :next)
    assert tree.update(reorder, nil)
    assert_operator tree.root.states[:revision], :>, first_revision
  end

  def test_invalid_and_self_targets_do_not_drop
    phases = []
    reorder = D::Reorder.new(threshold: 0,
      locate: ->(_point, source) { D::Target.new(source, :before) })
      .on_event { |event| phases << [event.phase, event.reason] }
    reorder.press(:same, T::Point.new(0, 0))
    reorder.move(T::Point.new(1, 0))
    refute reorder.release
    assert_includes phases, [:cancel, :no_target]

    assert_raises(ArgumentError) { reorder.press(nil, T::Point.new(0, 0)) }
    assert_raises(TypeError) { reorder.press(:source, Object.new) }
    invalid = D::Reorder.new(threshold: 0,
      locate: ->(*) { D::Target.new(:target, :around) })
    invalid.press(:source, T::Point.new(0, 0))
    assert_raises(ArgumentError) { invalid.move(T::Point.new(1, 0)) }
    assert_nil invalid.source_id
  end

  def test_invalid_new_operation_does_not_cancel_active_drag
    reorder = D::Reorder.new(locate: ->(*) {})
    point = T::Point.new(-8, -13)
    reorder.press(:source, point)

    assert_raises(ArgumentError) { reorder.press(nil, point) }
    assert_raises(TypeError) { reorder.move(Object.new) }
    assert_equal :source, reorder.source_id
    refute reorder.dragging?
  end

  def test_false_is_a_valid_stable_id
    dropped = nil
    reorder = D::Reorder.new(threshold: 0,
      locate: ->(*) { D::Target.new(:target, :after) }).on_drop { |event| dropped = event.source_id }

    reorder.press(false, T::Point.new(0, 0))
    reorder.move(T::Point.new(1, 0))

    assert reorder.release
    assert_equal false, dropped
  end

  def test_default_keymap_exposes_reorder_actions_only_in_context
    keymap = T::Input::Keymap.default_ui(platform: :linux)

    assert_equal :reorder_before, keymap.dispatch("alt-up", context: {reorderable: true})
    assert_nil keymap.dispatch("alt-up", context: {})
    assert_equal :reorder_after, keymap.dispatch("alt-down", context: {reorderable: true})
    assert_equal :cancel_reorder, keymap.dispatch("esc", context: {reorderable: true})
  end

  def test_keyboard_endpoint_is_a_no_op_and_escape_cancels_pointer_reorder
    drops = []
    reorder = D::Reorder.new(locate: ->(*) {}, keyboard: ->(*) {})
      .on_drop { |event| drops << event }

    refute reorder.action(:first, :reorder_before)
    assert_empty drops
    assert_equal "Cancelled moving first", reorder.announcement

    reorder.press(:first, T::Point.new(0, 0))
    assert reorder.action(:first, :cancel_reorder)
    assert_nil reorder.source_id
  end

  def test_virtual_list_target_lookup_does_not_render_offscreen_items
    rendered = []
    list = T::List.new(count: 100_000, estimated_height: 20) do |index|
      rendered << index
      T::Div.new.h(20).key(index)
    end.w(120).h(40)
    list.scroll_y = 1_000_000
    @window.draw { list }
    @window.tick
    reorder = D::Reorder.new(threshold: 0, locate: lambda { |point, _source|
      index = list.heights.index_at(list.scroll_y + point.y)
      D::Target.new(index, point.y < 20 ? :before : :after)
    })

    reorder.press(49_999, T::Point.new(1, 1))
    reorder.move(T::Point.new(1, 21))

    assert_operator rendered.length, :<, 20
    assert_equal 50_001, reorder.target.id
    assert_includes list.visible_range, 50_000
  end
end
