# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"

class AccessibilityTreeTest < Minitest::Test
  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 320, height: 200)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_window_builds_tree_and_notifies_only_on_differences
    button = Zaniah::UI::Button.new("Save")
    @window.draw { Zaniah::Div.new.child(button) }
    @window.tick
    assert_equal 1, @window.accessibility_revision
    assert_equal :button, @window.accessibility_tree.find { |node| node.label == "Save" }.role

    @window.request_frame
    @window.tick
    assert_equal 1, @window.accessibility_revision

    button.disabled
    @window.request_frame
    @window.tick
    assert_equal 2, @window.accessibility_revision
    assert_equal true, @window.accessibility_tree.find { |node| node.role == :button }.states[:disabled]
    assert_equal :updated, @window.accessibility_tree.changes.first.kind
  end

  def test_tree_reports_structural_additions_and_removals
    content = []
    @window.draw { Zaniah::Div.new.children(content) }
    @window.tick
    content << Zaniah::UI::Label.new("Ready")
    @window.request_frame
    @window.tick
    assert_equal :added, @window.accessibility_tree.changes.first.kind
    assert_equal "Ready", @window.accessibility_tree.root.children.first.label

    content.clear
    @window.request_frame
    @window.tick
    assert_equal :removed, @window.accessibility_tree.changes.first.kind
    assert_nil @window.accessibility_tree.root
  end

  def test_popup_participates_in_application_tree
    @window.draw { Zaniah::UI::Button.new("Open") }
    @window.context_menu([["Choose", -> {}]], position: Zaniah::Point.new(0, 0))
    @window.tick
    roles = @window.accessibility_tree.each.map { |node, _| node.role }
    assert_includes roles, :button
    assert_includes roles, :menu
  end

  def test_stable_ids_report_moves_and_keep_native_runtime_ids
    renderable = Struct.new(:items) do
      def accessibility_node(_context)
        Zaniah::Accessibility.node(role: :list, children: items.map do |id|
          Zaniah::Accessibility.node(role: :listitem, id: id, label: id.to_s)
        end)
      end
    end.new(%i[first second])
    tree = Zaniah::Accessibility::Tree.new
    assert tree.update(renderable, nil)
    before = Zaniah::Accessibility::NativeTree.new(tree.root)
    runtime_ids = before.to_h { |entry| [entry.node.id, entry.runtime_id] }

    renderable.items = %i[second first]
    assert tree.update(renderable, nil)
    assert_equal %i[second first], tree.changes.select { |change| change.kind == :moved }.map { |change| change.after.id }

    after = Zaniah::Accessibility::NativeTree.new(tree.root, previous: before)
    assert_equal runtime_ids, after.to_h { |entry| [entry.node.id, entry.runtime_id] }
    assert_nil Zaniah::Accessibility.node(role: :group, states: {id: :application_data}).id
  end

  def test_events_and_actions_are_deterministic
    renderable = Class.new do
      attr_accessor :revision
      attr_reader :performed

      def initialize = @revision = 1
      def accessibility_node(_context)
        Zaniah::Accessibility.node(role: :status, id: :result, label: "Moved",
          states: {live: :polite, revision: @revision}, actions: [:dismiss])
      end
      def accessibility_action(node, action)
        @performed = [node.id, action]
        true
      end
    end.new
    tree = Zaniah::Accessibility::Tree.new

    assert tree.update(renderable, nil)
    assert_equal %i[structure announcement], tree.events.map(&:kind)
    assert_equal [:result, :dismiss], (tree.perform(tree.root, :dismiss) && renderable.performed)
    refute tree.update(renderable, nil)
    assert_empty tree.events

    renderable.revision += 1
    assert tree.update(renderable, nil)
    assert_equal %i[property announcement], tree.events.map(&:kind)
    assert tree.events.all? { |event| event.id == :result }
  end

  def test_moving_and_updating_a_live_node_announces_once
    renderable = Struct.new(:items) do
      def accessibility_node(_context)
        Zaniah::Accessibility.node(role: :list, children: items.map do |id, label|
          Zaniah::Accessibility.node(role: id == :status ? :status : :listitem, id: id, label: label,
            states: id == :status ? {live: :polite} : {})
        end)
      end
    end.new([[:status, "Waiting"], [:other, "Other"]])
    tree = Zaniah::Accessibility::Tree.new
    tree.update(renderable, nil)

    renderable.items = [[:other, "Other"], [:status, "Ready"]]
    tree.update(renderable, nil)

    assert_equal 1, tree.events.count { |event| event.kind == :announcement }
    assert_equal %i[layout layout property announcement], tree.events.map(&:kind)
  end

  def test_unchanged_tree_rebinds_actions_to_the_latest_renderable
    renderable = Class.new do
      attr_reader :performed

      def accessibility_node(_context)
        Zaniah::Accessibility.node(role: :button, id: :save, label: "Save", actions: [:press])
      end

      def accessibility_action(_node, action)
        @performed = action
        true
      end
    end
    first = renderable.new
    second = renderable.new
    tree = Zaniah::Accessibility::Tree.new
    assert tree.update(first, nil)
    native_node = tree.root

    refute tree.update(second, nil)
    assert tree.perform(native_node, :press)
    assert_nil first.performed
    assert_equal :press, second.performed
  end

  def test_false_is_a_valid_and_unique_stable_id
    node = -> { Zaniah::Accessibility.node(role: :listitem, id: false) }
    tree = Zaniah::Accessibility::Tree.new

    assert tree.update(Struct.new(:node) { def accessibility_node(*) = node }.new(node.call), nil)
    assert_equal false, tree.root.id
    assert_raises(ArgumentError) do
      tree.update(Struct.new(:node) do
        def accessibility_node(*) = Zaniah::Accessibility.node(role: :list, children: [node, node])
      end.new(node.call), nil)
    end

    tree = Zaniah::Accessibility::Tree.new
    wrapper = Struct.new(:node) { def accessibility_node(*) = node }
    tree.update(wrapper.new(Zaniah::Accessibility.node(role: :list, children: [node.call])), nil)
    tree.update(wrapper.new(Zaniah::Accessibility.node(role: :list,
      children: [Zaniah::Accessibility.node(role: :listitem)])), nil)
    assert_equal %i[removed added], tree.changes.map(&:kind)
  end
end
