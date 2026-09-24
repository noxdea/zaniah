# frozen_string_literal: true

require "benchmark"
require_relative "../lib/zaniah"

def measure(scene)
  renderer = Zaniah::GPU::Software.new(800, 600)
  3.times { renderer.render(scene) }
  samples = Array.new(7) { Benchmark.realtime { renderer.render(scene) } }
  samples.sort.fetch(samples.length / 2) * 1_000
end

analytic = Zaniah::Scene.new
legacy = Zaniah::Scene.new
100.times do |index|
  x, y = (index % 10) * 78 + 8, (index / 10) * 56 + 8
  analytic.shadow(x, y, 48, 24, blur: 6, spread: 1, radius: 4)
  8.downto(1) do |step|
    amount = 1 + 6 * step / 8.0
    alpha = Math.exp(-2.0 * (step / 8.0)**2) / 10.0
    legacy.quad(x - amount, y - amount, 48 + 2 * amount, 24 + 2 * amount,
      color: Zaniah::Color.parse("#0006").opacity(alpha), radius: 4 + amount)
  end
end

old_ms, new_ms = measure(legacy), measure(analytic)
puts "100 shadows Software: legacy #{old_ms.round(2)} ms, analytic #{new_ms.round(2)} ms (#{(old_ms / new_ms).round(2)}x)"
abort "analytic shadows must be faster" unless new_ms < old_ms
