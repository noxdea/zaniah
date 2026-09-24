# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class MatcherTest < Minitest::Test
  UI = Zaniah::UI
  Input = Zaniah::Input

  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 640, height: 480)
  end

  def teardown
    @window.close
    @app.executor.shutdown
    Zaniah.configuration.matcher = nil
  end

  def render(component)
    @window.draw { component }
    @window.render(component, present: false)
    component
  end

  def test_substring_preserves_order_and_reports_utf8_byte_ranges
    matches = UI::Matcher::Substring.new.match("ru", ["Ruby", "Cruise", "Zig", "😀ruby"])
    assert_equal [0, 1, 3], matches.map(&:index)
    assert_equal [0...2, 1...3, 4...6], matches.map { |match| match.ranges.first }
    assert_equal [0, 1], UI::Matcher::Substring.new.match("", %w[Ruby Zig]).map(&:index)
    assert_equal [0...2], UI::Matcher::Substring.new.match("i", ["İstanbul"]).first.ranges
    assert_equal [["😀", false], ["ruby", true]], UI::Matcher.segments("😀ruby", [4...8])
  end

  def test_matcher_refines_only_when_query_extends_previous_query
    matcher = Class.new do
      attr_reader :calls

      def initialize = @calls = []
      def match(query, labels)
        @calls << [:match, query, labels]
        labels.each_index.map { |index| Zaniah::UI::Matcher::Match.new(index: index, score: 0.0, ranges: []) }
      end
      def refine(previous, query)
        @calls << [:refine, previous, query]
        previous
      end
    end.new
    session = UI::Matcher::Session.new(%w[Ruby Rust], matcher)
    first = session.results("r")
    assert_same first, session.results("r")
    assert_same first, session.results("ru")
    session.results("z")
    assert_equal %i[match refine match], matcher.calls.map(&:first)
    assert_same first, matcher.calls[1][1]
  end

  def test_matcher_session_does_not_keep_mutable_query_by_reference
    session = UI::Matcher::Session.new(%w[Ruby Zig], UI::Matcher::Substring.new)
    query = +"Ru"
    assert_equal [0], session.results(query).map(&:index)
    query.replace("Zi")
    assert_equal [1], session.results(query).map(&:index)
  end

  def test_palette_filters_accessibility_and_activates_selected_match
    called = []
    palette = render(UI::CommandPalette.new([
      ["Ruby Open", ->(*) { called << :open }],
      ["Zig Build", ->(*) { called << :zig }],
      ["Ruby Close", ->(*) { called << :close }]
    ], open: true))
    assert_equal true, palette.focus_handle.context[:in_palette]
    assert_equal true, @window.dispatcher.focused.owner.is_a?(Zaniah::Text)

    @window.input(Input::TextInput.new("Ruby"))
    @window.render(palette, present: false)
    list = palette.accessibility_node(nil).children.last
    assert_equal ["Ruby Open", "Ruby Close"], list.children.map(&:label)
    assert_equal "palette-option-0", list.states[:active_descendant]
    assert_equal "> Ruby\nRuby Open\nRuby Close", palette.tui_cells

    @window.input(Input::KeyDown.new("down", false))
    @window.render(palette, present: false)
    assert_equal "palette-option-2", palette.accessibility_node(nil).children.last.states[:active_descendant]
    @window.input(Input::KeyDown.new("enter", false))
    assert_equal [:close], called
    refute palette.open?
  end

  def test_palette_from_registry_disables_unavailable_commands
    @app.actions.register(:save, title: "Save", enabled: ->(_cx) { false }) { |_cx| flunk "disabled action ran" }
    @app.actions.register(:open, title: "Open") { |_cx| @opened = true }
    palette = render(UI::CommandPalette.from(@app.actions, open: true))
    list = palette.accessibility_node(nil).children.last
    assert_equal [true, false], list.children.map { |item| item.states[:disabled] }
    assert_equal "palette-option-1", list.states[:active_descendant]
    @window.input(Input::KeyDown.new("enter", false))
    assert @opened
  end

  def test_palette_from_registry_preserves_symbol_actions_for_focus_validation
    @app.actions.register(:save, title: "Save") { flunk "disabled command ran" }
    palette = render(UI::CommandPalette.from(@app.actions, open: true))
    handle = Input::FocusHandle.new(validate: ->(action) { action == :save ? false : nil })
    @window.dispatcher.focus(handle)

    assert_equal :disabled, @window.dispatcher.available?(:save)
    assert_equal true, palette.accessibility_node(nil).children.last.children.first.states[:disabled]
  end

  def test_palette_accessibility_press_runs_only_a_visible_result
    called = []
    palette = render(UI::CommandPalette.new([
      ["Ruby Open", ->(*) { called << :ruby }],
      ["Zig Build", ->(*) { called << :zig }]
    ], open: true))
    @window.input(Input::TextInput.new("zig"))
    @window.render(palette, present: false)
    list = @window.accessibility_tree.root.children.last
    assert_equal ["Zig Build"], list.children.map(&:label)
    assert Zaniah::Accessibility.perform(@window, list.children.first, :press)
    assert_equal [:zig], called
  end

  def test_combobox_uses_configured_matcher_and_highlights_ranges
    matcher = Class.new do
      def match(_query, labels)
        [Zaniah::UI::Matcher::Match.new(index: labels.length - 1, score: 1.0, ranges: [0...1])]
      end
    end.new
    Zaniah.configure { |config| config.matcher = matcher }
    combo = render(UI::Combobox.new(%w[Ruby Zig]))
    @window.dispatcher.focus(combo.focus_handle)
    @window.input(Input::KeyDown.new("down", false))
    @window.render(combo, present: false)
    assert_instance_of UI::HighlightedButton, combo.root.children.last.children.first
    @window.input(Input::KeyDown.new("enter", false))
    assert_equal "Zig", combo.value
  end
end
