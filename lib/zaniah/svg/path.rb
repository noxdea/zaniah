# frozen_string_literal: true

require "strscan"

module Zaniah
  class SVG
    class Path
      # SVG path grammar, including compact arc flags and smooth relative curves.
      NUMBER = /[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/
      def self.parse(source) = new(source).parse
      def initialize(source)
        @scanner, @outline = StringScanner.new(source), Alhena::Outline.new
        @x = @y = @start_x = @start_y = 0.0
        @previous, @control = nil, nil
      end

      def parse
        command, operations = nil, 0
        loop do
          separator
          break if @scanner.eos?
          explicit = @scanner.scan(/[a-zA-Z]/)
          command = explicit if explicit
          raise ArgumentError, "SVG path must start with moveto" if @previous.nil? && !%w[M m].include?(command)
          raise ArgumentError, "missing SVG path command" unless command
          operations += 1
          raise ArgumentError, "SVG path is too complex" if operations > 100_000
          relative, type = command == command.downcase, command.upcase
          case type
          when "M", "L", "T"
            x, y = point(relative)
            if type == "M"
              @outline.move_to(x, y)
              @start_x, @start_y = x, y
            elsif type == "T"
              control = %w[Q T].include?(@previous) ? reflected : [@x, @y]
              @outline.quad_to(*control, x, y)
              @control = control
            else
              @outline.line_to(x, y)
            end
            @x, @y = x, y
          when "H"
            @x = number + (relative ? @x : 0)
            @outline.line_to(@x, @y)
          when "V"
            @y = number + (relative ? @y : 0)
            @outline.line_to(@x, @y)
          when "C"
            a, b, endpoint = point(relative), point(relative), point(relative)
            @outline.cubic_to(*a, *b, *endpoint)
            @control, (@x, @y) = b, endpoint
          when "S"
            a = %w[C S].include?(@previous) ? reflected : [@x, @y]
            b, endpoint = point(relative), point(relative)
            @outline.cubic_to(*a, *b, *endpoint)
            @control, (@x, @y) = b, endpoint
          when "Q"
            a, endpoint = point(relative), point(relative)
            @outline.quad_to(*a, *endpoint)
            @control, (@x, @y) = a, endpoint
          when "A"
            rx, ry, rotation, large, sweep = number, number, number, flag, flag
            endpoint = point(relative)
            arc(rx, ry, rotation, large, sweep, *endpoint)
            @x, @y = endpoint
          when "Z"
            raise ArgumentError, "closepath cannot repeat without a command" unless explicit
            @outline.close
            @x, @y = @start_x, @start_y
            command = nil
          else raise ArgumentError, "unsupported SVG path command #{command}"
          end
          @previous = type
          command = relative ? "l" : "L" if type == "M"
        end
        @outline
      end

      private

      def separator = @scanner.skip(/[\s,]*/)
      def number
        separator
        token = @scanner.scan(NUMBER)
        raise ArgumentError, "invalid SVG path number near #{@scanner.peek(20).inspect}" unless token
        value = Float(token)
        raise ArgumentError, "SVG coordinate is out of range" unless value.finite? && value.abs <= 1e9
        value
      end
      def flag
        separator
        token = @scanner.scan(/[01]/)
        raise ArgumentError, "invalid SVG arc flag" unless token
        token == "1"
      end
      def point(relative) = [number + (relative ? @x : 0), number + (relative ? @y : 0)]
      def reflected = [2 * @x - @control[0], 2 * @y - @control[1]]

      def arc(rx, ry, rotation, large, sweep, x, y)
        return if x == @x && y == @y
        rx, ry = rx.abs, ry.abs
        return @outline.line_to(x, y) if rx.zero? || ry.zero?
        phi = rotation * Math::PI / 180
        cos, sin = Math.cos(phi), Math.sin(phi)
        dx, dy = (@x - x) / 2, (@y - y) / 2
        px, py = cos * dx + sin * dy, -sin * dx + cos * dy
        scale = px * px / (rx * rx) + py * py / (ry * ry)
        rx, ry = rx * Math.sqrt(scale), ry * Math.sqrt(scale) if scale > 1
        rx2, ry2 = rx * rx, ry * ry
        numerator = [rx2 * ry2 - rx2 * py * py - ry2 * px * px, 0].max
        coefficient = Math.sqrt(numerator / (rx2 * py * py + ry2 * px * px)) * (large == sweep ? -1 : 1)
        cxp, cyp = coefficient * rx * py / ry, -coefficient * ry * px / rx
        cx, cy = cos * cxp - sin * cyp + (@x + x) / 2, sin * cxp + cos * cyp + (@y + y) / 2
        ux, uy, vx, vy = (px - cxp) / rx, (py - cyp) / ry, (-px - cxp) / rx, (-py - cyp) / ry
        theta = Math.atan2(uy, ux)
        delta = Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        delta -= 2 * Math::PI if !sweep && delta.positive?
        delta += 2 * Math::PI if sweep && delta.negative?
        segments = (delta.abs / (Math::PI / 2)).ceil
        step = delta / segments
        mapped = ->(a, b) { [cx + cos * rx * a - sin * ry * b, cy + sin * rx * a + cos * ry * b] }
        segments.times do
          ending, factor = theta + step, 4.0 / 3 * Math.tan(step / 4)
          a = mapped.call(Math.cos(theta) - factor * Math.sin(theta), Math.sin(theta) + factor * Math.cos(theta))
          b = mapped.call(Math.cos(ending) + factor * Math.sin(ending), Math.sin(ending) - factor * Math.cos(ending))
          endpoint = mapped.call(Math.cos(ending), Math.sin(ending))
          @outline.cubic_to(*a, *b, *endpoint)
          theta = ending
        end
      end
    end
  end
end
