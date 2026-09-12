# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"
require "zaniah/devtools"

class DevToolsTest < Minitest::Test
  class FakeWatcher
    attr_reader :closed
    def initialize(events) = @events = events
    def poll(timeout: 0) = @events.shift || []
    def close = @closed = true
  end

  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 320, height: 200)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_f12_toggles_inspector_and_collects_frame_stats
    inspector = Zaniah::DevTools.attach(@window)
    @window.draw { Zaniah::Div.new.child(Zaniah::UI::Button.new("Save").key(:save)) }
    @window.tick
    refute inspector.visible?
    assert_equal "Div", inspector.snapshot.name
    assert_operator @window.frame_stats[:command_count], :>, 0

    @window.input(Zaniah::Input::KeyDown.new("f12", false))
    @window.tick
    assert inspector.visible?
    assert_equal inspector, @window.devtools
    commands = @window.scene.commands
    assert (0...commands.length).step(4).any? { |index| commands[index + 2] == Zaniah::Scene::LAYER_DEBUG }
  end

  def test_hot_reload_loads_changed_ruby_and_preserves_entities
    entity = @app.new_entity { {count: 1} }
    watcher = FakeWatcher.new([[Zaniah::Platform::FileEvent.new(:modified, "/tmp/example.rb", nil)]])
    loaded, reloaded = [], nil
    reload = Zaniah::DevTools::HotReload.new(@app, [], watcher: watcher, loader: ->(path) { loaded << path }) { |paths| reloaded = paths }

    assert_equal ["/tmp/example.rb"], reload.poll
    assert_equal loaded, reloaded
    assert_equal({count: 1}, @app.read(entity))
    assert @window.dirty?
    reload.close
    assert watcher.closed
  end
end
