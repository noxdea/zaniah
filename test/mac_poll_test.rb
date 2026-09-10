# frozen_string_literal: true

require_relative "test_helper"

class MacPollTest < Minitest::Test
  def setup
    skip "Cocoa event loop is macOS only" unless RUBY_PLATFORM.include?("darwin")
    require "zaniah/platform/mac"
    @app_class = Zaniah::Platform::Mac::App
    @previous_app = @app_class.instance_variable_get(:@instance)
    @app = @app_class.allocate
    @app_class.instance_variable_set(:@instance, @app)
    @polls = []
    polls = @polls
    @app.define_singleton_method(:poll) { |wait: 0| polls << wait }
    @window = Zaniah::Platform::Mac::Window.allocate
    @window.instance_variable_set(:@closed, false)
    @window.instance_variable_set(:@dirty, false)
  end

  def teardown
    @app_class&.instance_variable_set(:@instance, @previous_app)
  end

  def test_standalone_tick_polls_and_reports_native_callback_errors
    ticks = 0
    @window.on_tick { ticks += 1 }
    @window.tick
    assert_equal [0], @polls
    assert_equal 1, ticks
    @window.tick(poll_events: false)
    assert_equal [0], @polls
    assert_equal 2, ticks
    error = RuntimeError.new("native callback failed")
    @window.instance_variable_set(:@native_error, error)
    assert_same error, assert_raises(RuntimeError) { @window.tick(poll_events: false) }
    assert_equal 2, ticks
  end

  def test_window_loop_polls_once_per_tick_without_changing_waits
    ticks = 0
    @window.on_tick do
      ticks += 1
      @window.request_frame
      @window.instance_variable_set(:@closed, true) if ticks == 2
    end
    # No draw is necessary: render-independent event-loop contract.
    @window.run
    assert_equal 2, ticks
    assert_equal [0.05, 0.05], @polls
    @window.instance_variable_set(:@closed, false)
    @window.on_tick { @window.instance_variable_set(:@closed, true) }
    @window.request_frame
    @window.run
    assert_equal 0, @polls.last
    assert_equal 3, @polls.length
  end

  def test_application_loop_does_not_poll_again_for_each_window
    registry = Zaniah::Platform::Mac::WINDOWS
    previous = registry.dup
    second = Zaniah::Platform::Mac::Window.allocate
    second.instance_variable_set(:@closed, false)
    ticks = []
    [@window, second].each_with_index do |window, index|
      window.on_tick { ticks << index; window.instance_variable_set(:@closed, true) }
    end
    registry.replace({1 => @window, 2 => @window, 3 => second})
    @app.run
    assert_equal [0.05], @polls
    assert_equal [0, 1], ticks
  ensure
    registry&.replace(previous) if previous
  end
end
