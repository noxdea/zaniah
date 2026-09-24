# frozen_string_literal: true

require "test_helper"

class ArabicJoiningTest < Minitest::Test
  Joining = Zaniah::Unicode::ArabicJoining

  def test_unicode_joining_types_include_controls_and_transparent_marks
    assert_equal "D", Joining.type("ب".ord)
    assert_equal "R", Joining.type("ا".ord)
    assert_equal "T", Joining.type("َ".ord)
    assert_equal "C", Joining.type(0x200D)
    assert_equal "U", Joining.type(0x200C)
    assert_equal "U", Joining.type(" ".ord)
  end

  def test_forms_follow_logical_neighbors_across_transparent_marks
    assert_equal ["init", "medi", "fina"], Joining.forms("ببب").values
    assert_equal ["init", "fina"], Joining.forms("بَت").values
    assert_equal ["isol", "isol"], Joining.forms("ب‌ت").values # ZWNJ
    assert_equal ["init", "fina"], Joining.forms("ب‍ت").values # ZWJ
  end

  def test_right_joining_letter_cannot_join_following_letter
    assert_equal ["isol", "isol"], Joining.forms("اب").values
    assert_equal ["init", "fina"], Joining.forms("با").values
    assert_equal ["init"], Joining.forms("ب‍").values
    assert_equal ["fina"], Joining.forms("‍ب").values
  end

  def test_offsets_are_utf8_bytes
    assert_equal [1, 3], Joining.forms("aبب").keys
  end
end
