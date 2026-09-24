# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"

class InspectionTest < Minitest::Test
  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 200, height: 100)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_snapshot_exposes_rendered_entries_and_frontmost_hit
    back = Zaniah::Div.new.key(:back).test_id("back").w(40).h(30).on_click { }
    front = Zaniah::Div.new.key(:front).test_id("front").w(40).h(30)
      .bg("#f00").tooltip("Open").context_menu([["Open", -> { }], ["Disabled", nil]])
      .focusable.on_click { }
    root = Zaniah::Div.new.child(back).child(front)
    @window.render(root)
    @window.dispatcher.focus(front.focus_handle)

    snapshot = Zaniah::Inspection.snapshot(@window)
    entry = snapshot.find(test_id: "front")
    assert_same root, snapshot.root.element
    assert_equal "Div", snapshot.root.type
    assert_equal ["back", "front"], snapshot.where(type: Zaniah::Div).drop(1).map(&:test_id)
    assert_equal :front, entry.key
    assert_equal "#f00", entry.style[:background]
    assert_equal "Open", entry.tooltip
    assert_equal [["Open", true], ["Disabled", false]], entry.context_menu
    assert_equal [:click], entry.handlers
    assert entry.focusable?
    assert entry.focused?
    assert_equal entry, snapshot.at(Zaniah::Point.new(5, 35))
    assert_equal 1, snapshot.frame.number
    assert snapshot.frame.stats.frozen?
    assert snapshot.root.children.frozen?
    assert snapshot.text_runs.frozen?
    assert_equal Zaniah::Inspection::Entry, Zaniah::DevTools::Entry if defined?(Zaniah::DevTools::Entry)
  end

  def test_snapshot_copies_overlay_and_text_state
    @window.offer_tooltip("Help", position: Zaniah::Point.new(1, 2))
    @window.render(Zaniah::Div.new)
    @window.text_runs << [1, 2, +"Live", "#fff"]
    snapshot = Zaniah::Inspection.snapshot(@window)

    assert_equal "Help", snapshot.overlays.tooltip[:text]
    assert snapshot.overlays.tooltip.frozen?
    assert snapshot.overlays.tooltip[:text].frozen?
    assert_equal "Live", snapshot.text_runs.first[2]
    assert snapshot.text_runs.first.frozen?
    @window.text_runs.first[2].replace("Changed")
    assert_equal "Live", snapshot.text_runs.first[2]
    assert_raises(FrozenError) { snapshot.text_runs << [] }
  end

  def test_idle_and_accessibility_perform
    assert_nil Zaniah::Inspection.snapshot(@window).root
    refute Zaniah::Inspection.idle?(@app)
    @window.draw { Zaniah::Div.new }
    @window.tick
    assert Zaniah::Inspection.idle?(@app)
    @window.request_frame
    refute Zaniah::Inspection.idle?(@app)
    @window.tick
    assert Zaniah::Inspection.idle?(@app)
    assert_equal false, Zaniah::Inspection.perform(@window, nil, :press)
  end

  def test_bundled_font_path_exists
    assert File.file?(Zaniah.bundled_font_path)
  end

  def test_accessibility_snapshot_query_preserves_tree_filtering
    save = Zaniah::Accessibility.node(role: :button, label: "Save", states: {enabled: true})
    root = Zaniah::Accessibility.node(role: :group, children: [save])
    snapshot = Zaniah::Inspection::AccessibilitySnapshot.new(root: root)

    assert_equal [[save, [0]]], snapshot.query(role: :button, label: /sav/i, states: {enabled: true})
    assert_empty snapshot.query(states: {missing: nil})
    assert_raises(ArgumentError) { snapshot.query(label: 123) }
  end

  def test_at_maps_built_component_hits_to_the_component
    button = Zaniah::UI::Button.new("Save").test_id("save")
    @window.render(button)
    snapshot = Zaniah::Inspection.snapshot(@window)

    assert_equal button, snapshot.at(Zaniah::Point.new(5, 5)).element
  end

  def test_at_uses_the_same_transform_and_clip_as_pointer_dispatch
    element = Zaniah::Div.new.w(40).h(30).style(transform: Zaniah::Transform.translate(50, 0)).on_click { }
    @window.render(element)
    snapshot = Zaniah::Inspection.snapshot(@window)

    assert_equal element, snapshot.at(Zaniah::Point.new(60, 5)).element
    assert_nil snapshot.at(Zaniah::Point.new(20, 5))
  end

  def test_accessibility_snapshot_does_not_change_when_source_mutates
    label = +"Save"
    node = Zaniah::Accessibility.node(role: :button, label: label, actions: [:press])
    renderable = Struct.new(:node, :called) do
      def request_layout(*) = Zaniah::Layout::Node.new(style: Zaniah::Layout::Style.new)
      def prepaint(*) = nil
      def paint(*) = nil
      def accessibility_node(*) = node
      def accessibility_action(_node, action) = (self.called = action; true)
    end.new(node)
    @window.render(renderable)
    snapshot = Zaniah::Inspection.snapshot(@window)
    label.replace("Delete")

    assert_equal "Save", snapshot.accessibility.root.label
    assert snapshot.accessibility.root.label.frozen?
    assert Zaniah::Inspection.perform(@window, snapshot.accessibility.root, :press)
    assert_equal :press, renderable.called
  end
end
