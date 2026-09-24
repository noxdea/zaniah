# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
require "alhena"

provider_name = if ARGV.delete("--directwrite") || RUBY_PLATFORM.match?(/mswin|mingw/)
  :directwrite
elsif ARGV.delete("--freetype") || !RUBY_PLATFORM.include?("darwin")
  :freetype
else
  :coretext
end
require "zaniah/platform/#{ {directwrite: 'windows/direct_write', freetype: 'linux/free_type', coretext: 'mac/core_text'}.fetch(provider_name) }"
path = File.expand_path(ARGV.fetch(0))
db = Zaniah::TextSystem::FontDB.new(paths: [path])
font = db.open(path)
provider = case provider_name
when :directwrite then Zaniah::Platform::Windows::DirectWrite.new(font_db: db)
when :freetype then Zaniah::Platform::Linux::FreeType.new
else Zaniah::Platform::Mac::CoreText.new
end
glyph = font.glyph_id("A".ord)
bitmap = provider.rasterize(font, glyph, size: 32)
raise "empty native font bitmap" unless bitmap.width.positive? && bitmap.height.positive? && bitmap.coverage.bytes.any?(&:positive?)
reference = font.rasterize(glyph, size: 32)
puts "Alhena #{reference.width}x#{reference.height}, bearing=#{reference.left},#{reference.top} | #{provider_name} #{bitmap.width}x#{bitmap.height}, bearing=#{bitmap.left},#{bitmap.top}"
left, right = reference.to_ascii.lines, bitmap.to_ascii.lines
[left.length, right.length].max.times { |index| puts "#{left[index].to_s.chomp.ljust(34)} | #{right[index]}" }
provider.close
