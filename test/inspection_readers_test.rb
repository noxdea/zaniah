# frozen_string_literal: true

require_relative "test_helper"

class InspectionReadersTest < Minitest::Test
  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 160, height: 100)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_element_exposes_tooltip_and_context_menu
    element = Zaniah::Div.new
    assert_nil element.tooltip_text
    assert_nil element.context_menu_items

    items = [["Open", -> {}]]
    element.tooltip("Help").context_menu(items)
    assert_equal "Help", element.tooltip_text
    assert_same items, element.context_menu_items
  end

  def test_window_exposes_current_root_and_frame_before_callback
    assert_nil @window.last_root
    assert_equal 0, @window.frame_number

    seen = []
    @window.on_frame { |element, _clear| seen << [@window.last_root, @window.frame_number, element] }
    first = Zaniah::Div.new
    second = Zaniah::Div.new
    @window.render(first)
    @window.render(second)

    assert_equal [[first, 1, first], [second, 2, second]], seen
    assert_same second, @window.last_root
    assert_equal 2, @window.frame_number
  end

  def test_tooltip_state_is_an_immutable_copy
    assert_nil @window.tooltip_state
    @window.offer_tooltip("Help", position: Zaniah::Point.new(4, 5))
    state = @window.tooltip_state

    assert_equal "Help", state[:text]
    assert_equal Zaniah::Point.new(4, 5), state[:position]
    assert_equal false, state[:shown]
    assert state.frozen?
    assert state[:text].frozen?
    assert_raises(FrozenError) { state[:shown] = true }
    assert_raises(FrozenError) { state[:text] << "!" }
    assert_equal false, @window.tooltip_state[:shown]
  end

  def test_executor_idle_checks_foreground_queue
    executor = @app.executor
    assert executor.idle?
    called = false
    executor.post { called = true }
    refute executor.idle?
    executor.drain
    assert called
    assert executor.idle?
  end

  def test_accessibility_query_filters_role_label_and_states
    tree = Zaniah::Accessibility::Tree.new
    assert_empty tree.query(role: :button)

    save = Zaniah::Accessibility.node(role: :button, label: "Save", states: {enabled: true})
    cancel = Zaniah::Accessibility.node(role: :button, label: "Cancel", states: {enabled: false})
    unnamed = Zaniah::Accessibility.node(role: :button)
    root = Zaniah::Accessibility.node(role: :group, children: [save, cancel, unnamed])
    renderable = Struct.new(:node) { def accessibility_node(*) = node }.new(root)
    tree.update(renderable, nil)

    assert_equal [[save, [0]]], tree.query(role: :button, label: "Save")
    assert_equal [[save, [0]]], tree.query(label: /sav/i, states: {enabled: true})
    assert_equal [[cancel, [1]]], tree.query(role: :button, states: {enabled: false})
    assert_empty tree.query(states: {missing: nil})
    assert_empty tree.query(role: :checkbox)
    assert_raises(ArgumentError) { tree.query(label: 12) }
  end
end
