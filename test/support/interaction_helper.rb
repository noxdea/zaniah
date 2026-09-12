# frozen_string_literal: true

module Zaniah
  class TestClock
    def initialize(now = 0.0) = @now = now.to_f
    def call = @now
    def advance(seconds) = @now += seconds
  end

  module InteractionHelper
    def move_to(x, y)
      @pointer = Point.new(x, y)
      @window.input(Input::MouseMove.new(@pointer, []))
    end

    def click(x, y, button: :left)
      move_to(x, y)
      @window.input(Input::MouseDown.new(@pointer, button, [], 1))
      @window.input(Input::MouseUp.new(@pointer, button, []))
    end

    def key(keystroke) = @window.input(Input::KeyDown.new(keystroke, false))
    def type(text) = @window.input(Input::TextInput.new(text))

    def scroll(dx, dy)
      @window.input(Input::ScrollWheel.new(@pointer || Point.new(0, 0), Point.new(dx, dy), :move, []))
    end

    def frame! = @window.tick

    def advance(seconds)
      @clock.advance(seconds)
      @window.request_frame
    end
  end
end
