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
end
