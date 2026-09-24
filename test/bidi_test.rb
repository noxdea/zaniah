# frozen_string_literal: true

require_relative "test_helper"

class BidiTest < Minitest::Test
  def test_unicode_18_character_conformance
    checked, failures = 0, []
    path = File.expand_path("fixtures/unicode/BidiCharacterTest.txt", __dir__)
    File.foreach(path) do |line|
      next if line.start_with?("#") || line.strip.empty?
      columns = line.split("#", 2).first.split(";").map(&:strip)
      points = columns[0].split.map { |hex| hex.to_i(16) }
      text = points.pack("U*")
      direction = {"0" => :ltr, "1" => :rtl, "2" => :auto}.fetch(columns[1])
      actual = Zaniah::Unicode::Bidi.resolve(text, direction: direction)
      expected_levels = columns[3].split.map { |value| value == "x" ? nil : value.to_i }
      expected_order = columns[4].split.map(&:to_i)
      unless actual.paragraph_level == columns[2].to_i && actual.levels == expected_levels && actual.visual_order == expected_order
        failures << [checked + 1, points.map { |point| point.to_s(16) }.join(" "),
          [columns[2].to_i, expected_levels, expected_order],
          [actual.paragraph_level, actual.levels, actual.visual_order]]
      end
      checked += 1
      break if ENV["BIDI_LIMIT"] && checked >= Integer(ENV["BIDI_LIMIT"])
    end
    assert_operator checked, :>, 90_000 unless ENV["BIDI_LIMIT"]
    assert_empty failures.first(10), "#{failures.length}/#{checked} failed; first ten: #{failures.first(10).inspect}"
  end
end
