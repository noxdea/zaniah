# frozen_string_literal: true

require_relative "../test_helper"

class GoldenBasicTest < Zaniah::UITest
  def test_div_and_text
    assert_golden("basic/div-and-text") do
      Zaniah::Div.new.w(180).h(56).p(12).bg("#345477").rounded(8)
        .child(Zaniah::Text.new("Zaniah", size: 20, color: "#edf2f7"))
    end
  end

  def test_clock_advances_without_sleeping
    before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    advance(1.0)
    assert_equal 1.0, @clock.call
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - before, :<, 0.1
  end
end
