# frozen_string_literal: true

# Regenerate with: ruby tools/generate_arabic_joining.rb
# Source and terms: https://www.unicode.org/Public/18.0.0/ucd/
require "net/http"
require "uri"

version = "18.0.0"
url = "https://www.unicode.org/Public/#{version}/ucd/extracted/DerivedJoiningType.txt"
response = Net::HTTP.get_response(URI(url))
raise "Could not fetch #{url}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

ranges = []
response.body.each_line do |line|
  next unless line =~ /\A([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([CLRDT])\b/
  first = Regexp.last_match(1).to_i(16)
  last = (Regexp.last_match(2) || Regexp.last_match(1)).to_i(16)
  joining_type = Regexp.last_match(3)
  ranges << [first, last, joining_type]
end
raise "No joining types in #{url}" if ranges.empty?
ranges = ranges.sort_by(&:first).each_with_object([]) do |range, merged|
  if merged.last && merged.last[1] + 1 == range[0] && merged.last[2] == range[2]
    merged.last[1] = range[1]
  else
    merged << range
  end
end

path = File.expand_path("../lib/zaniah/unicode/arabic_joining_data.rb", __dir__)
File.write(path, <<~RUBY)
  # frozen_string_literal: true
  # Generated from Unicode #{version} UCD; do not edit by hand.
  # https://www.unicode.org/terms_of_use.html
  module Zaniah::Unicode::ArabicJoiningData
    VERSION = #{version.inspect}
    RANGES = #{ranges.inspect}.freeze
  end
RUBY
puts "Unicode #{version}: #{ranges.length} joining-type ranges"
