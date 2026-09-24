# frozen_string_literal: true

# Run this file alone to check the public API consumed by downstream gems.
require_relative "test_helper"

class InspectionContractTest < Minitest::Test
  def test_public_method_signatures
    assert_equal [[:req, :window]], Zaniah::Inspection.method(:snapshot).parameters
    assert_equal [[:req, :app]], Zaniah::Inspection.method(:idle?).parameters
    assert_equal [[:req, :window], [:req, :node], [:req, :action]], Zaniah::Inspection.method(:perform).parameters
    assert_equal [], Zaniah.method(:bundled_font_path).parameters

    snapshot = Zaniah::Inspection.snapshot(Zaniah::Platform::Headless::Window.new)
    assert_instance_of Zaniah::Inspection::Snapshot, snapshot
    assert_instance_of Zaniah::Inspection::Overlays, snapshot.overlays
    assert_instance_of Zaniah::Inspection::FrameInfo, snapshot.frame
    assert_instance_of Zaniah::Inspection::AccessibilitySnapshot, snapshot.accessibility
    assert_nil snapshot.root
    assert_equal 0, snapshot.frame.number
    assert_equal [], snapshot.where(type: Zaniah::Div)
    assert_nil snapshot.find(test_id: "missing")
    assert_nil snapshot.at(Zaniah::Point.new(0, 0))
    assert_equal [[:key, :test_id], [:key, :type]], snapshot.method(:find).parameters
    assert_equal [[:key, :test_id], [:key, :type]], snapshot.method(:where).parameters
    assert_equal [[:req, :point]], snapshot.method(:at).parameters
    assert_equal [[:key, :role], [:key, :label], [:key, :states]], snapshot.accessibility.method(:query).parameters
  end

  def test_entry_shape
    window = Zaniah::Platform::Headless::Window.new
    window.render(Zaniah::Div.new.test_id("root"))
    entry = Zaniah::Inspection.snapshot(window).root
    assert_instance_of Zaniah::Inspection::Entry, entry
    assert_equal "root", entry.test_id
    assert_kind_of Zaniah::Bounds, entry.bounds
    assert_kind_of Hash, entry.style
    assert_respond_to entry, :focusable?
    assert_respond_to entry, :focused?
    assert_kind_of Array, entry.children
  end
end
