# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class ExtendedComponentsTest < Minitest::Test
  include Zaniah::InteractionHelper

  def setup
    @clock = Zaniah::TestClock.new
    @app = Zaniah::App.new(clock: @clock)
    @window = @app.open_window(width: 800, height: 600)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_segmented_control_keyboard_and_accessibility
    seen = []
    control = Zaniah::UI::SegmentedControl.new([["Day", :day], ["Week", :week]], value: :day)
      .on_change { |value, *_| seen << value }
    @window.render(control, present: false)
    @window.dispatcher.focus(control.focus_handle)
    key("right")
    assert_equal :week, control.value
    assert_equal [:week], seen
    @window.render(control, present: false)
    node = @window.accessibility_tree.root
    assert_equal :radiogroup, node.role
    assert_equal [false, true], node.children.map { |child| child.states[:checked] }
    assert Zaniah::Accessibility.perform(@window, node.children.first, :select)
    assert_equal :day, control.value
  end

  def test_alert_live_region_and_dismissal
    alert = Zaniah::UI::Alert.new("Saved", message: "Ready", variant: :success, dismissible: true, live: true)
    @window.render(alert, present: false)
    node = @window.accessibility_tree.root
    assert_equal :alert, node.role
    assert_equal true, node.states[:live]
    assert Zaniah::Accessibility.perform(@window, node.children.last, :press)
    assert alert.dismissed?
    assert_equal "", alert.tui_cells
    @window.render(alert, present: false)
    assert_nil @window.accessibility_tree.root
  end

  def test_hover_card_uses_injected_clock_for_open_and_close_grace
    card = Zaniah::UI::HoverCard.new(Zaniah::UI::Label.new("Details"),
      anchor: Zaniah::Bounds.new(20, 20, 80, 30), open_delay: 0.5, close_delay: 0.25)
    @window.draw { card }
    frame!
    move_to(30, 30)
    frame!
    refute card.open?
    advance(0.49)
    frame!
    refute card.open?
    advance(0.01)
    frame!
    assert card.open?
    assert_equal :dialog, @window.accessibility_tree.root.role
    move_to(700, 500)
    frame!
    assert card.open?
    advance(0.25)
    frame!
    refute card.open?
  end

  def test_hover_card_opens_for_keyboard_focus
    trigger = Zaniah::UI::Button.new("Help")
    card = Zaniah::UI::HoverCard.new(Zaniah::UI::Label.new("Details"), anchor: trigger, open_delay: 0.5)
    @window.draw { card }
    frame!
    @window.dispatcher.focus(trigger.focus_handle, origin: :keyboard)
    @window.request_frame
    frame!
    advance(0.5)
    frame!
    assert card.open?
    assert_equal :dialog, @window.accessibility_tree.root.role
  end

  def test_calendar_navigation_bounds_range_and_semantics
    calendar = Zaniah::UI::Calendar.new(value: "2026-09-20", min: "2026-09-18", max: "2026-10-02",
      week_start: 1, month_names: Array.new(12) { |index| "M#{index + 1}" })
    @window.render(calendar, present: false)
    assert_equal "M9 2026", calendar.tui_cells.lines.first.strip
    assert_equal "Mo", calendar.tui_cells.lines[1].strip[0, 2]
    @window.dispatcher.focus(calendar.focus_handle)
    key("down")
    assert_equal Date.new(2026, 9, 27), calendar.cursor
    key("enter")
    assert_equal Date.new(2026, 9, 27), calendar.value
    @window.render(calendar, present: false)
    node = @window.accessibility_tree.root
    assert_equal :grid, node.role
    assert_equal 42, node.children.length
    assert_equal [], node.children.find { |child| child.value == "2026-09-17" }.actions
    target = node.children.find { |child| child.value == "2026-09-24" }
    assert Zaniah::Accessibility.perform(@window, target, :select)
    assert_equal Date.new(2026, 9, 24), calendar.value
  end

  def test_date_range_picker_selects_sorted_range_and_reports_combobox
    picker = Zaniah::UI::DateRangePicker.new(value: ["2026-09-01", "2026-09-30"])
    assert_equal "Date range: [2026-09-01 – 2026-09-30]", picker.tui_cells
    @window.render(picker, present: false)
    node = @window.accessibility_tree.root
    assert_equal :combobox, node.role
    assert Zaniah::Accessibility.perform(@window, node, :press)
    @window.render(picker, present: false)
    assert picker.open?
    calendar = picker.instance_variable_get(:@calendar)
    assert calendar.send(:select, Date.new(2026, 10, 10), Zaniah::FrameContext.new(@window))
    assert calendar.send(:select, Date.new(2026, 10, 1), Zaniah::FrameContext.new(@window))
    assert_equal [Date.new(2026, 10, 1), Date.new(2026, 10, 10)], picker.value
    refute picker.open?
  end
end
