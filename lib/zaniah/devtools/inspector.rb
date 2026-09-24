# frozen_string_literal: true

module Zaniah
  module DevTools
    Entry = Inspection::Entry

    class Inspector
      attr_reader :window, :snapshot, :selected

      def initialize(window, visible: false, stats: true)
        @window, @visible, @snapshot = window, !!visible, nil
        @stats = StatsOverlay.new if stats
        previous = window.instance_variable_get(:@on_frame)
        window.on_frame do |element, clear|
          previous&.call(element, clear)
          frame(element)
        end
        window.devtools = self
      end

      def visible? = @visible

      def toggle
        @visible = !@visible
        window.request_frame
        self
      end

      def handle_input(event)
        return false unless event.is_a?(Input::KeyDown) && Input::Keystroke.normalize(event.keystroke) == "f12"
        toggle
        true
      end

      def frame(_element)
        @inspection = Inspection.snapshot(window)
        @snapshot = @inspection.root
        return unless visible?
        @selected = hovered
        paint_highlight(@selected.bounds) if @selected&.bounds
        paint_panel
      end

      private

      def hovered
        @inspection.at(window.pointer_position) || @snapshot
      end

      def paint_highlight(bounds)
        window.scene.layer(Scene::LAYER_DEBUG) do
          window.scene.quad(bounds.x, bounds.y, bounds.width, bounds.height,
            color: "#38bdf833", border_width: 1, border_color: "#38bdf8")
        end
      end

      def paint_panel
        scene = window.scene
        width, line_height = [window.content_size.width * 0.42, 360].min, 17
        x = window.content_size.width - width
        lines = flatten(@snapshot).first(((window.content_size.height - 70) / line_height).floor)
        scene.layer(Scene::LAYER_DEBUG) do
          scene.quad(x, 0, width, window.content_size.height, color: "#111827ee", border_width: 1, border_color: "#38bdf8")
          lines.each_with_index { |(entry, depth), index| text("#{"  " * depth}#{entry.name}#{entry.key ? " [#{entry.key}]" : ""}", x + 8, 8 + index * line_height) }
          if @selected
            text("bounds: #{@selected.bounds&.to_h || "none"}", x + 8, window.content_size.height - 48)
            text("style: #{@selected.style.reject { |_key, value| value.nil? }.first(3).to_h}", x + 8, window.content_size.height - 31)
          end
          @stats&.paint(window, x: x + 8, y: window.content_size.height - 68)
        end
      end

      def flatten(entry, depth = 0, result = [])
        return result unless entry
        result << [entry, depth]
        entry.children.each { |child| flatten(child, depth + 1, result) }
        result
      end

      def text(value, x, y)
        return unless window.text_system
        line = window.text_system.layout_line(value.to_s, size: 11)
        window.text_system.paint_line(window.scene, line, x: x, y: y + line.ascent, color: "#e5e7eb")
      end
    end
  end
end
