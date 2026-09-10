# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
require "alhena"

provider_name = ARGV.delete("--freetype") ? :freetype : :coretext
require "zaniah/platform/#{provider_name == :freetype ? 'linux/free_type' : 'mac/core_text'}"
provider = provider_name == :freetype ? Zaniah::Platform::Linux::FreeType.new : Zaniah::Platform::Mac::CoreText.new
font = Alhena::Font.open(ARGV.fetch(0))
bitmap = provider.rasterize(font, font.glyph_id("A"), size: 32)
raise "empty native font bitmap" unless bitmap.width.positive? && bitmap.height.positive? && bitmap.coverage.bytes.any?(&:positive?)
puts "#{provider_name}: #{bitmap.width}x#{bitmap.height}, bearing=#{bitmap.left},#{bitmap.top}"
puts bitmap.to_ascii
provider.close
