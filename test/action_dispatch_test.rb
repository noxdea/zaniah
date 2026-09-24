# frozen_string_literal: true

require_relative "test_helper"

class ActionDispatchTest < Minitest::Test
  def test_keyboard_and_menu_reach_same_focused_handler
    keymap = Zaniah::Input::Keymap.new.bind("ctrl-s", :save)
    app = Zaniah::App.new
    window = app.open_window(backend: :headless, keymap: keymap)
    seen = []
    element = Zaniah::Div.new.focusable(validate: ->(action) { action == :save ? true : nil }) do |action|
      seen << action
      true
    end
    window.dispatcher.focus(element.focus_handle)

    assert_equal :enabled, window.dispatcher.available?(:save)
    window.input(Zaniah::Input::KeyDown.new("ctrl-s", false))
    assert window.dispatcher.perform(:save, source: :menu)
    assert_equal [:save, :save], seen
  ensure
    window&.close
  end

  def test_validation_blocks_execution_and_nil_defers_to_app
    app = Zaniah::App.new
    window = app.open_window(backend: :headless)
    seen = []
    app.actions.register(:save, enabled: ->(cx) { cx.window == window }, checked: ->(_cx) { true }) do |cx|
      seen << cx.window
    end
    element = Zaniah::Div.new.focusable(validate: ->(action) { action == :save ? false : nil }) { seen << :local }
    window.dispatcher.focus(element.focus_handle)

    assert_equal :disabled, window.dispatcher.available?(:save)
    refute window.dispatcher.perform(:save, source: :palette)
    assert_empty seen

    element.focus_handle.validate = ->(_action) { nil }
    element.focus_handle.on_action = ->(_action) { flunk "nil validation should skip this handler" }
    assert_equal :enabled, window.dispatcher.available?(:save)
    assert window.dispatcher.perform(:save, source: :context_menu)
    assert_equal [window], seen
    assert_equal true, window.dispatcher.checked?(:save)
    assert_equal :unhandled, window.dispatcher.available?(:missing)
    assert_nil window.dispatcher.checked?(:missing)
  ensure
    window&.close
  end

  def test_disabled_app_command_and_unvalidated_focus_handler
    app = Zaniah::App.new
    window = app.open_window(backend: :headless)
    app.actions.register(:save, enabled: ->(_cx) { false }) { flunk "disabled command ran" }
    assert_equal :disabled, window.dispatcher.available?(:save)
    refute window.dispatcher.perform(:save)

    seen = []
    handle = Zaniah::Input::FocusHandle.new
    handle.on_action = ->(action) { seen << action; true }
    window.dispatcher.focus(handle)
    assert_equal :disabled, window.dispatcher.available?(:save)
    assert window.dispatcher.perform(:save)
    assert_equal [:save], seen
  ensure
    window&.close
  end

  def test_non_focusable_ancestor_receives_action
    dispatcher = Zaniah::Input::Dispatcher.new(keymap: Zaniah::Input::Keymap.new.bind("esc", :dismiss))
    scope = Zaniah::Input::FocusHandle.new(focusable: false)
    child = Zaniah::Input::FocusHandle.new(parent: scope)
    seen = []
    scope.on_action = ->(action) { seen << action; true }
    dispatcher.focus(child)

    assert_equal :dismiss, dispatcher.key("esc")
    assert_equal [:dismiss], seen
  end

  def test_repeated_focusable_preserves_validator_unless_explicitly_cleared
    validator = ->(_action) { false }
    element = Zaniah::Div.new.focusable(validate: validator) { true }
    element.focusable(context: {in_text_field: true})
    assert_same validator, element.focus_handle.validate

    element.focusable(validate: nil)
    assert_nil element.focus_handle.validate
  end

  def test_direct_platform_window_has_focus_actions_without_app_registry
    window = Zaniah::Platform.open_window(backend: :headless)
    seen = []
    handle = Zaniah::Input::FocusHandle.new
    handle.on_action = ->(action) { seen << action; true }
    window.dispatcher.focus(handle)

    assert window.dispatcher.perform(:save, source: :menu)
    assert_equal [:save], seen
    assert_equal :unhandled, window.dispatcher.available?(:save)
  ensure
    window&.close
  end
end
