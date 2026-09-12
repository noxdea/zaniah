# frozen_string_literal: true

module Zaniah
  module DevTools
    class StatsOverlay
      def paint(window, x:, y:)
        stats = window.frame_stats
        value = format("%.0f fps  %.2f ms  %d commands", stats[:fps], stats[:frame_ms], stats[:command_count])
        return unless window.text_system
        line = window.text_system.layout_line(value, size: 11)
        window.text_system.paint_line(window.scene, line, x: x, y: y + line.ascent, color: "#67e8f9")
      end
    end
  end
end
