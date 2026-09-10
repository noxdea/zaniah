# frozen_string_literal: true

require "benchmark"
require "zaniah"
require "zaniah/list"

window = Struct.new(:content_size).new(Zaniah::Size.new(800, 600))
context = Struct.new(:window).new(window)
rendered = 0
list = nil
construction = Benchmark.realtime do
  list = Zaniah::List.new(count: 1_000_000, estimated_height: 24) do |index|
    rendered += 1
    Zaniah::Div.new.h(index.even? ? 20 : 28)
  end.w(800).h(600)
end
samples = 100.times.map do |index|
  list.scroll_y = index * 240_000
  Benchmark.realtime do
    node = list.request_layout(context)
    Zaniah::Layout::Engine.new.compute(node, width: 800, height: 600)
  end
end
puts "million-row index construction: #{(construction * 1000).round(3)} ms"
puts "visible frame median: #{(samples.sort[50] * 1000).round(3)} ms"
puts "average constructed rows per frame: #{rendered / 100.0}"
raise "virtualization budget exceeded" if rendered > 5000
