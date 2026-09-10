# frozen_string_literal: true

module Zaniah
  class SceneRenderer
    def initialize(device) = @device = device
    def render(scene, clear: "#0000") = @device.render(scene, clear: clear)
  end
end
