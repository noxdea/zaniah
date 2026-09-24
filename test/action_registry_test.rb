# frozen_string_literal: true

require_relative "test_helper"

class ActionRegistryTest < Minitest::Test
  def test_legacy_registration_and_app_registry
    app = Zaniah::App.new
    assert_same app.actions, app.actions

    handler = ->(value) { value.upcase }
    assert_equal ["Save", handler], app.actions.register(:save, description: "Save", &handler)
    assert_equal({"save" => "Save"}, app.actions.entries)
    assert app.actions.entries.frozen?
    assert_equal "DONE", app.actions.call("save", "done")

    command = app.actions.command(:save)
    assert_instance_of Zaniah::Input::Command, command
    assert_equal :save, command.name
    assert_equal "Save", command.title
    assert_nil command.category
    assert_same handler, command.handler
  end

  def test_command_metadata_and_title_alias
    registry = Zaniah::Input::ActionRegistry.new
    enabled = ->(context) { context[:ready] }
    checked = ->(context) { context[:selected] }
    registry.register(:toggle, description: "Old", title: "Toggle", category: "View",
      enabled: enabled, checked: checked) { :toggled }

    command = registry.command("toggle")
    assert_equal "Toggle", command.title
    assert_equal "View", command.category
    assert_same enabled, command.enabled
    assert_same checked, command.checked
    assert_equal({"toggle" => "Toggle"}, registry.entries)
    assert_equal :toggled, registry.call(:toggle)
    assert_nil registry.command(:missing)
  end
end
