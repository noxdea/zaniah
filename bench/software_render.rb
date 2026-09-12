# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zaniah"
require_relative "support/budget"

scene = Zaniah::Scene.new
gradient_scenes = {
  "axis" => Zaniah::Gradient.linear(stops: [[0, "#0ea5e9"], [1, "#8b5cf6"]]),
  "angled" => Zaniah::Gradient.linear(angle: 25, stops: [[0, "#0ea5e9"], [1, "#8b5cf6"]]),
  "radial" => Zaniah::Gradient.radial(stops: [[0, "#0ea5e9"], [1, "#8b5cf6"]])
}.transform_values { Zaniah::Scene.new }
20.times do |row|
  20.times do |column|
    color = row.even? ? "#345477" : "#202936"
    scene.quad(column * 40, row * 30, 40, 30, color: color)
    gradient_scenes.each_value { |gradient_scene| gradient_scene.quad(column * 40, row * 30, 40, 30, color: color) }
  end
end
gradient_scenes.each do |kind, gradient_scene|
  gradient = {
    "axis" => Zaniah::Gradient.linear(stops: [[0, "#0ea5e9"], [1, "#8b5cf6"]]),
    "angled" => Zaniah::Gradient.linear(angle: 25, stops: [[0, "#0ea5e9"], [1, "#8b5cf6"]]),
    "radial" => Zaniah::Gradient.radial(stops: [[0, "#0ea5e9"], [1, "#8b5cf6"]])
  }.fetch(kind)
  100.times do |index|
    gradient_scene.quad((index % 10) * 80, (index / 10) * 60, 80, 60, color: gradient)
  end
end
device = Zaniah::GPU::Software.new(800, 600)
baseline = Bench.budget("software render 800x600", 40.0, samples: 5) { device.render(scene, clear: "#181b20") }
gradient_scenes.each do |kind, gradient_scene|
  Bench.budget("software render with 100 #{kind} gradients", baseline + 5.0, samples: 5) { device.render(gradient_scene, clear: "#181b20") }
end
device.release
