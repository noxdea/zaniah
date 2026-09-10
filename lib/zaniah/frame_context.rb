# frozen_string_literal: true

module Zaniah
  class FrameContext
    attr_reader :window, :scene, :dispatcher, :text_system

    def initialize(window)
      @window, @scene = window, window.scene
      @dispatcher, @text_system = window.dispatcher, window.text_system
    end

    def state(key, &initial) = @window.element_state(key, &initial)
  end
end
