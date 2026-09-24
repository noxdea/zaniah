# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "support/budget"

scene = Zaniah::Scene.new
draw = lambda do
  scene.clear
  1_000.times { |index| scene.quad(index % 100, index / 100, 1, 1, color: "#789") }
end

Bench.budget("vector disabled 1000 quads", 6.0, warmup: 10, samples: 21, &draw)
scene.vector_sink = Zaniah::Vector::Recorder.new(width: 100, height: 10)
Bench.budget("vector recorded 1000 quads", 20.0, warmup: 10, samples: 21, &draw)
