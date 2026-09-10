# frozen_string_literal: true

require_relative "test_helper"

class KeymapPrecedenceTest < Minitest::Test
  def test_later_chord_prefix_overrides_an_earlier_complete_binding
    map = Zaniah::Input::Keymap.new.bind("ctrl-k", :hover).bind("ctrl-s", :save)
      .bind("ctrl-k ctrl-s", :save_all)
    assert_equal :pending, map.dispatch("ctrl-k", now: 1)
    assert_equal :save_all, map.dispatch("ctrl-s", now: 1.1)
    assert_equal :save, map.dispatch("ctrl-s", now: 1.2)
  end

  def test_later_complete_binding_overrides_an_earlier_chord_prefix
    map = Zaniah::Input::Keymap.new.bind("ctrl-k ctrl-s", :save_all)
      .bind("ctrl-k", :hover).bind("ctrl-s", :save)
    assert_equal :hover, map.dispatch("ctrl-k", now: 1)
    assert_equal :save, map.dispatch("ctrl-s", now: 1.1)
  end

  def test_precedence_applies_at_each_position_of_a_longer_chord
    map = Zaniah::Input::Keymap.new.bind("ctrl-k ctrl-s", :save_all)
      .bind("ctrl-k ctrl-s ctrl-f", :save_folder)
    assert_equal :pending, map.dispatch("ctrl-k", now: 1)
    assert_equal :pending, map.dispatch("ctrl-s", now: 1.1)
    assert_equal :save_folder, map.dispatch("ctrl-f", now: 1.2)
  end

  def test_inactive_later_context_does_not_shadow_matching_bindings
    map = Zaniah::Input::Keymap.new.bind("ctrl-k", :hover)
      .bind("ctrl-k ctrl-s", :save_all, context: "Editor && !vim_mode")
      .bind("ctrl-k", :terminal_action, context: "Terminal")
    assert_equal :hover, map.dispatch("ctrl-k", context: {"Editor" => true, "vim_mode" => true}, now: 1)
    assert_equal :pending, map.dispatch("ctrl-k", context: {"Editor" => true}, now: 2)
    assert_equal :save_all, map.dispatch("ctrl-s", context: {"Editor" => true}, now: 2.1)
    assert_equal :terminal_action, map.dispatch("ctrl-k", context: {"Terminal" => true}, now: 3)
  end

  def test_unknown_second_stroke_restarts_matching_and_timeout_discards_prefix
    map = Zaniah::Input::Keymap.new.bind("ctrl-k", :hover).bind("ctrl-s", :save)
      .bind("ctrl-k ctrl-s", :save_all).bind("f8 f9", :other)
    assert_equal :pending, map.dispatch("ctrl-k", now: 1)
    assert_equal :pending, map.dispatch("f8", now: 1.1)
    assert_equal :other, map.dispatch("f9", now: 1.2)
    assert_equal :pending, map.dispatch("ctrl-k", now: 2)
    assert_nil map.dispatch("f7", now: 2.1)
    assert_equal :save, map.dispatch("ctrl-s", now: 2.2)
    assert_equal :pending, map.dispatch("ctrl-k", now: 3)
    assert_equal :save, map.dispatch("ctrl-s", now: 5)
  end

  def test_later_null_binding_clears_the_pending_sequence
    map = Zaniah::Input::Keymap.new.bind("ctrl-k ctrl-s", :save_all)
      .bind("ctrl-k", nil).bind("ctrl-s", :save)
    assert_nil map.dispatch("ctrl-k", now: 1)
    assert_equal :save, map.dispatch("ctrl-s", now: 1.1)
  end
end
