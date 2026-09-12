# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/ui"

class AnimationTest < Minitest::Test
  T = Zaniah

  def setup
    @clock = T::TestClock.new
    @app = T::App.new(clock: @clock)
    @window = @app.open_window(width: 100, height: 100)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_animator_interpolates_and_returns_to_idle
    completed = false
    @window.animator.animate(:value, from: 0, to: 10, duration: 1, easing: :linear) { completed = true }
    @clock.advance(0.5)
    assert_in_delta 5, @window.animator.sample[:value]
    assert @window.animation_active?
    @clock.advance(0.5)
    assert_equal 10, @window.animator.sample[:value]
    refute @window.animation_active?
    assert completed
  end

  def test_easing_spring_and_supported_values
    assert_in_delta 0.5, T::Easing.cubic_bezier(0.42, 0, 0.58, 1).call(0.5), 0.001
    assert_operator T::Easing.spring.call(1), :>, 0.99
    assert_equal T::Color.new(0.5, 0, 0.5, 1), T::Animation.interpolate(T::Color.parse("#f00"), T::Color.parse("#00f"), 0.5)
    assert_equal T::Length.new(15.0, :px), T::Animation.interpolate(T::Length.new(10, :px), T::Length.new(20, :px), 0.5)
  end

  def test_reduced_motion_finishes_immediately
    @window.animator.reduced_motion = true
    called = false
    @window.animator.animate(:value, from: 0, to: 1, duration: 10) { called = true }
    assert_equal 1, @window.animator.value(:value)
    refute @window.animator.active?
    assert called
  end

  def test_theme_reduced_motion_applies_before_component_layout
    theme = T::Theme.dark
    @app.global(:theme, theme.with(motion: theme.motion.with(reduced: true)))
    modal = T::UI::Modal.new(T::UI::Label.new("Body"))
    @window.draw { modal }
    @window.tick

    assert_equal 1.0, @window.animator.value([:overlay, modal.object_id])
    refute @window.animation_active?
  end

  def test_keyed_transition_uses_previous_resolved_style
    color, current = T::Color.parse("#000"), nil
    @window.draw { current = T::Div.new.key(:box).bg(color).transition(:background, duration: 1, easing: :linear) }
    @window.tick
    color = T::Color.parse("#fff")
    @window.request_frame
    @window.tick
    assert_equal T::Color.parse("#000"), current.resolved_style[:background]
    @clock.advance(0.5)
    @window.tick
    assert_equal T::Color.new(0.5, 0.5, 0.5, 1), current.resolved_style[:background]
    @clock.advance(0.5)
    @window.tick
    refute @window.dirty?
    refute @window.animation_active?
  end

  def test_transition_without_key_is_immediate
    color, current = T::Color.parse("#000"), nil
    @window.draw { current = T::Div.new.bg(color).transition(:background, duration: 1) }
    @window.tick
    color = T::Color.parse("#fff")
    @window.request_frame
    @window.tick
    assert_equal color, current.resolved_style[:background]
    refute @window.animation_active?
  end

  def test_keyed_children_enter_move_and_exit
    phase = 0
    @window.draw do
      child = T::Div.new.key(:row).style(position: :absolute, left: phase == 1 ? 20 : 0, width: 10, height: 10)
      T::Div.new.key(:list).children(phase == 2 ? [] : [child])
    end
    @window.tick
    refute @window.animation_active?
    phase = 1
    @window.request_frame
    @window.tick
    assert @window.animation_active?
    phase = 2
    @window.request_frame
    @window.tick
    assert @window.animation_active?
    @clock.advance(1)
    @window.tick
    refute @window.animation_active?
    refute @window.dirty?
  end

  def test_inertial_scroll_uses_the_shared_animator
    state = T::ScrollState.new(axis: :vertical)
    state.update(content_size: T::Size.new(100, 500), viewport_size: T::Size.new(100, 100))
    state.glide_by(10, animator: @window.animator, key: :scroll, duration: 1)
    assert_equal 10, state.offset.y
    @clock.advance(0.5)
    @window.animator.sample
    state.sample_glide
    assert_operator state.offset.y, :>, 10
    assert_operator state.offset.y, :<, 40
  end

  def test_modal_and_collapsible_animate_visibility
    modal = T::UI::Modal.new(T::UI::Label.new("Body"))
    @window.draw { modal }
    @window.tick
    @clock.advance(1)
    @window.tick
    modal.close
    assert modal.visible?
    @clock.advance(1)
    @window.tick
    refute modal.visible?

    collapsible = T::UI::Collapsible.new("More", T::UI::Label.new("Body"))
    @window.draw { collapsible }
    @window.request_frame
    @window.tick
    collapsible.open
    @window.request_frame
    @window.tick
    assert @window.animation_active?
    @clock.advance(1)
    @window.tick
    refute @window.animation_active?
  end
end
