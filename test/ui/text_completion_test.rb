# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class TextCompletionTest < Minitest::Test
  T = Zaniah

  def setup
    @app = T::App.new(clock: T::TestClock.new)
    @window = @app.open_window(width: 640, height: 480)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def render(field)
    @window.draw { field }
    @window.request_frame
    @window.tick
    field
  end

  def test_status_is_visible_and_described_to_assistive_technology
    field = render(T::UI::TextField.new("tcp", label: "Filter").status(:warning, message: "Unknown field"))
    assert_equal :warning, field.status_kind
    assert_includes field.tui_cells, "! Unknown field"
    assert_equal "Unknown field", field.accessibility_node(nil).states[:description]
    refute field.accessibility_node(nil).states[:invalid]
    field.status(:error, message: "Invalid syntax")
    assert field.accessibility_node(nil).states[:invalid]
    field.status(:success)
    assert_includes field.tui_cells, "✓"
    assert_raises(ArgumentError) { field.status(:bad) }
  end

  def test_completion_replaces_only_token_and_restores_caret_after_rebuild
    provider = Object.new
    def provider.complete(text, caret)
      raise "incorrect query" unless text == "日本 tcp.po == 443" && caret == 12
      Zaniah::UI::Completion.new(range: 7...13, items: [{label: "tcp.port", detail: "uint16"}, {label: "tcp.port_name"}])
    end
    field = render(T::UI::TextField.new("日本 tcp.po == 443").completion(provider))
    @window.dispatcher.focus(field.focus_handle)
    field.request_completion(caret: 12)
    render(field)
    @window.input(T::Input::KeyDown.new("down", false))
    @window.input(T::Input::KeyDown.new("tab", false))
    assert_equal "日本 tcp.port_name == 443", field.value
    render(field)
    assert_equal 20, field.caret
    assert_equal field.focus_handle, @window.dispatcher.focused
  end

  def test_completion_rejects_ranges_that_split_unicode_and_can_be_dismissed
    provider = Object.new
    def provider.complete(*) = Zaniah::UI::Completion.new(range: 1...3, items: [{label: "bad"}])
    field = render(T::UI::TextField.new("日本").completion(provider))
    assert_raises(ArgumentError) { field.request_completion(caret: 0) }
    def provider.complete(*) = Zaniah::UI::Completion.new(range: 0...6, items: [{label: "Japan"}])
    field.request_completion(caret: 6)
    @window.dispatcher.focus(field.focus_handle)
    @window.input(T::Input::KeyDown.new("esc", false))
    refute field.completing?
    assert_equal "日本", field.value
  end
end
