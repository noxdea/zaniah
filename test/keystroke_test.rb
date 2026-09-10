# frozen_string_literal: true
require_relative "test_helper"

class KeystrokeTest < Minitest::Test
  def test_modified_minus_survives_normalization_and_keymap_dispatch
    normalizer = Zaniah::Input::Keystroke
    assert_equal "-", normalizer.normalize("-")
    assert_equal "alt--", normalizer.normalize("alt--")
    assert_equal "ctrl-shift--", normalizer.normalize("shift-control--")
    keymap = Zaniah::Input::Keymap.new.bind("alt--", :shrink)
    assert_equal :shrink, keymap.dispatch("alt--")
  end
end
