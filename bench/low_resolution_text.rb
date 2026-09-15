# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "support/budget"
require "alhena"

outlines = [
  Alhena::Outline.new.move_to(0, 0).line_to(12, 0).line_to(12, 2).line_to(0, 2).close,
  Alhena::Outline.new.move_to(16, 0).line_to(34, 0).line_to(34, 2).line_to(16, 2).close,
  Alhena::Outline.new.move_to(38, 0).line_to(47, 0).line_to(47, 2).line_to(38, 2).close
].freeze
cache = nil

Bench.budget("generate 10000 low-resolution text rows", 200.0, samples: 7,
  setup: lambda {
    cache&.close
    cache = Zaniah::TextSystem::LowResolutionTextCache.new(
      width: 80, height: 2, scale: 1, capacity: 10_000, max_bytes: 2 << 20
    )
  }) do
  10_000.times { |line| cache.texture(line, outlines: outlines) }
end

Bench.budget("regenerate one edited low-resolution text row", 1.0, samples: 11) do
  cache.invalidate(5_000)
  cache.texture(5_000, outlines: outlines)
end

raise "low-resolution row cache exceeded its byte limit" if cache.bytesize > cache.max_bytes
cache.close
