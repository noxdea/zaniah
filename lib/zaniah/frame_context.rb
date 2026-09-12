# frozen_string_literal: true

module Zaniah
  class FrameContext
    attr_reader :window, :scene, :dispatcher, :text_system, :interactivity

    def initialize(window)
      @window, @scene = window, window.scene
      @dispatcher, @text_system = window.dispatcher, window.text_system
      @interactivity = Interactivity.new
    end

    def state(key, &initial) = @window.element_state(key, &initial)
    def theme = @window.app&.global(:theme) || Theme.dark
  end
end
