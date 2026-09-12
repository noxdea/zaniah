# frozen_string_literal: true

require_relative "text_renderer"
require_relative "input_decoder"

module Zaniah
  module Platform
    module TUI
      class Window < Headless::Window
        def initialize(input: $stdin, output: $stdout, **options)
          @input, @output = input, output
          super(**options)
          @text_system = TextRenderer.new
          @input_decoder = InputDecoder.new { |event| self.input(event) }
        end

        def run
          require "io/console"
          raise Error, "TUI requires a terminal" unless @input.tty? && @output.tty?
          begin
            @output.write("\e[?1049h\e[?25l\e[?2004h\e[?1002h\e[?1006h")
            @output.flush
            @input.raw do
              until closed?
                tick
                if IO.select([@input], nil, nil, animation_active? ? 0 : 0.05)
                  data = @input.readpartial(4096)
                  feed_input(data)
                else
                  @input_decoder.flush_escape
                end
              end
            end
          ensure
            @output.write("\e[?1006l\e[?1002l\e[?2004l\e[?25h\e[?1049l")
            @output.flush
          end
        end

        def feed_input(bytes) = @input_decoder.feed(bytes)

        def render(element, **options)
          super(element, **options, present: false)
          rows = Array.new((content_size.height / 20).ceil) { Array.new((content_size.width / 8).ceil, " ") }
          colors = Array.new(rows.length) { Array.new(rows.first.length) }
          (@text_system.runs.empty? ? @text_runs : @text_system.runs).each do |x, y, text, color, clip|
            row, col = (y / 20).floor, (x / 8).floor
            next if row.negative? || !rows[row] || !text
            next if clip && (y < clip.y || y >= clip.bottom)
            first = clip ? [0, (clip.x / 8.0).ceil].max : 0
            last = clip ? [rows[row].length, (clip.right / 8).floor].min : rows[row].length
            text.each_grapheme_cluster do |char|
              break if col >= rows[row].length
              char = char.gsub(/[\x00-\x1f\x7f]/) { |control| control == "\x7f" ? "␡" : (0x2400 + control.ord).chr(Encoding::UTF_8) }
              width = Unicode.width(char)
              next if width.zero?
              break if col + width > last
              if col < first
                col += width
                next
              end
              rows[row][col - 1] = " " if col.positive? && rows[row][col].empty?
              rows[row][col + 1] = " " if rows[row][col + 1] == ""
              rows[row][col] = char if col >= 0
              colors[row][col] = color
              (1...width).each { |offset| rows[row][col + offset] = "" if col + offset >= 0 }
              col += width
            end
          end
          palette = {}
          lines = rows.each_with_index.map do |cells, row|
            current, line = nil, +""
            cells.each_with_index do |char, col|
              next if char.empty?
              color = colors[row][col] || "#ddd"
              if color != current
                line << (palette[color] ||= "\e[38;2;#{Color.parse(color).to_a.first(3).map { |value| (value * 255).round }.join(';')}m")
                current = color
              end
              line << char
            end
            line
          end
          @output.write("\e[H" + lines.join("\r\n") + "\e[0m")
          @output.write("\e[#{(@ime_state.y / 20).floor + 1};#{(@ime_state.x / 8).floor + 1}H\e[?25h") if @ime_state && @output.tty?
          @output.flush
        end
      end
    end
  end
end
