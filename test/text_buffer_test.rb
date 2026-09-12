# frozen_string_literal: true

require_relative "test_helper"

class TextBufferTest < Minitest::Test
  def test_grapheme_navigation_and_edit_boundaries
    text = "e\u0301👩‍👩‍👧‍👦x"
    buffer = Zaniah::TextBuffer.new(text)
    first = "e\u0301".bytesize
    family = "👩‍👩‍👧‍👦".bytesize
    assert_equal first, buffer.next_boundary(0)
    assert_equal first + family, buffer.next_boundary(first)
    assert_equal first, buffer.previous_boundary(first + family)
    assert_raises(ArgumentError) { buffer.insert(1, "!") }
  end

  def test_edits_undo_redo_lines_and_composition
    now = 0.0
    buffer = Zaniah::TextBuffer.new("", clock: -> { now })
    buffer.insert(0, "a")
    now += 0.1
    buffer.insert(1, "b")
    assert_equal "ab", buffer.to_s
    assert_equal "", buffer.undo.to_s
    assert_equal "ab", buffer.redo.to_s
    buffer.replace(0...1, "A").insert(2, "\n日本")
    assert_equal 1, buffer.line_at(buffer.bytesize)
    assert_equal 6, buffer.offset_at(1, 1)
    buffer.set_composition("語", selection: [3, 0])
    assert_equal "A語b\n日本", buffer.preview(1)
    buffer.commit_composition(1)
    assert_equal "A語b\n日本", buffer.to_s
  end

  def test_selection_normalization_and_word_boundaries
    selection = Zaniah::TextSelection.new(8, 2)
    assert_equal 2...8, selection.range
    assert_equal Zaniah::TextSelection.new(2, 8), selection.normalized
    assert selection.collapsed? == false
    assert_equal 0...6, Zaniah::Unicode.word_range_at("日本abc", 3)
    assert_equal 6...9, Zaniah::Unicode.word_range_at("日本abc", 7)
  end
end
