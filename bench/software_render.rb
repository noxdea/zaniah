# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zaniah"
require_relative "support/budget"

scene = Zaniah::Scene.new
gradient_scene = Zaniah::Scene.new
20.times do |row|
  20.times do |column|
    color = row.even? ? "#345477" : "#202936"
    scene.quad(column * 40, row * 30, 40, 30, color: color)
    gradient_scene.quad(column * 40, row * 30, 40, 30, color: color)
  end
end
100.times do |index|
  gradient_scene.quad((index % 10) * 80, (index / 10) * 60, 80, 60,
    color: Zaniah::Gradient.linear(stops: [[0, "#0ea5e9"], [1, "#8b5cf6"]]))
end
device = Zaniah::GPU::Software.new(800, 600)
baseline = Bench.budget("software render 800x600", 40.0, samples: 5) { device.render(scene, clear: "#181b20") }
Bench.budget("software render with 100 gradients", baseline + 5.0, samples: 5) { device.render(gradient_scene, clear: "#181b20") }
device.release
