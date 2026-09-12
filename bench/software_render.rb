# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zaniah"
require_relative "support/budget"

scene = Zaniah::Scene.new
20.times do |row|
  20.times { |column| scene.quad(column * 40, row * 30, 40, 30, color: row.even? ? "#345477" : "#202936") }
end
device = Zaniah::GPU::Software.new(800, 600)
Bench.budget("software render 800x600", 40.0, samples: 5) { device.render(scene, clear: "#181b20") }
device.release
