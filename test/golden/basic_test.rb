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

  def test_color_difference_fails_and_writes_diagnostics
    name = "basic/difference-probe"
    expected = Zaniah::PNG.encode(2, 2, ([0, 0, 0, 255] * 4).pack("C*"))
    actual = Zaniah::PNG.encode(2, 2, ([255, 0, 0, 255] * 4).pack("C*"))
    paths = %w[expected actual diff].map { |kind| File.join(Zaniah::UITest::DIFFS, "#{name}.#{kind}.png") }

    assert_raises(Minitest::Assertion) { send(:compare_golden, name, expected, actual, 2) }
    paths.each { |path| assert File.file?(path), path }
  ensure
    paths&.each { |path| FileUtils.rm_f(path) }
  end
end
