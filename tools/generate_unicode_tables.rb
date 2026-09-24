# frozen_string_literal: true

# Regenerate with: ruby tools/generate_unicode_tables.rb
# Source and terms: https://www.unicode.org/Public/18.0.0/ucd/
require "net/http"
require "uri"
require "fileutils"

version = "18.0.0"
base = "https://www.unicode.org/Public/#{version}/ucd"
fetch = ->(path) { Net::HTTP.get(URI("#{base}/#{path}")) }
root = File.expand_path("..", __dir__)

classes = Array.new(0x110000, :L)
source = fetch.call("extracted/DerivedBidiClass.txt")
source.each_line do |line|
  next unless line =~ /\A# \@missing: ([0-9A-F]+)\.\.([0-9A-F]+); ([\w_]+)/
  code = {"Right_To_Left" => :R, "Arabic_Letter" => :AL, "European_Terminator" => :ET}.fetch(Regexp.last_match(3), :L)
  (Regexp.last_match(1).to_i(16)..Regexp.last_match(2).to_i(16)).each { |point| classes[point] = code }
end
source.each_line do |line|
  next unless line =~ /\A([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Z][A-Z0-9]*)\b/
  first = Regexp.last_match(1).to_i(16)
  last = (Regexp.last_match(2) || Regexp.last_match(1)).to_i(16)
  code = Regexp.last_match(3).to_sym
  (first..last).each { |point| classes[point] = code }
end

ranges = []
classes.each_with_index do |code, point|
  next if code == :L
  if ranges.last && ranges.last[1] == point - 1 && ranges.last[2] == code
    ranges.last[1] = point
  else
    ranges << [point, point, code]
  end
end

brackets = {}
fetch.call("BidiBrackets.txt").each_line do |line|
  next unless line =~ /\A([0-9A-F]+)\s*;\s*([0-9A-F]+)\s*;\s*([oc])\b/
  brackets[Regexp.last_match(1).to_i(16)] = [Regexp.last_match(2).to_i(16), Regexp.last_match(3).to_sym]
end
mirrors = {}
fetch.call("BidiMirroring.txt").each_line do |line|
  next unless line =~ /\A([0-9A-F]+)\s*;\s*([0-9A-F]+)\b/
  mirrors[Regexp.last_match(1).to_i(16)] = Regexp.last_match(2).to_i(16)
end

output = File.join(root, "lib/zaniah/unicode/bidi_data.rb")
FileUtils.mkdir_p(File.dirname(output))
File.write(output, <<~RUBY)
  # frozen_string_literal: true
  # Generated from Unicode #{version} UCD; do not edit by hand.
  # https://www.unicode.org/terms_of_use.html
  module Zaniah::Unicode::BidiData
    VERSION = #{version.inspect}
    CLASS_RANGES = #{ranges.inspect}.freeze
    BRACKETS = #{brackets.inspect}.freeze
    MIRRORS = #{mirrors.inspect}.freeze
  end
RUBY

fixture = File.join(root, "test/fixtures/unicode/BidiCharacterTest.txt")
FileUtils.mkdir_p(File.dirname(fixture))
File.write(fixture, fetch.call("BidiCharacterTest.txt"))
puts "Unicode #{version}: #{ranges.length} ranges, #{brackets.length} brackets, #{mirrors.length} mirrors"
