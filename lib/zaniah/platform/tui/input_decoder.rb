# frozen_string_literal: true

module Zaniah
  module Platform
    module TUI
      # Decode terminal input bytes, never executable terminal output strings.
      class InputDecoder
        KEYS = {"A" => "up", "B" => "down", "C" => "right", "D" => "left", "H" => "home", "F" => "end",
                "P" => "f1", "Q" => "f2", "R" => "f3", "S" => "f4", "Z" => "tab"}.freeze
        TILDE_KEYS = {1 => "home", 2 => "insert", 3 => "delete", 4 => "end", 5 => "pageup", 6 => "pagedown", 7 => "home", 8 => "end",
                      11 => "f1", 12 => "f2", 13 => "f3", 14 => "f4", 15 => "f5", 17 => "f6", 18 => "f7", 19 => "f8", 20 => "f9", 21 => "f10", 23 => "f11", 24 => "f12"}.freeze
        attr_reader :buffer

        def initialize(&emit)
          @buffer, @emit = +"".b, emit
        end

        def feed(bytes)
          @buffer << bytes.b
          loop do
            break if @buffer.empty?
            if @buffer.start_with?("\e[200~")
              ending = @buffer.index("\e[201~", @paste_scan || 6)
              raise Error, "terminal paste exceeds 16 MiB" if @buffer.bytesize > 16_777_216
              unless ending
                @paste_scan = [@buffer.bytesize - 5, 6].max
                break
              end
              @paste_scan = nil
              value = @buffer.byteslice(6, ending - 6).force_encoding("UTF-8").scrub
              @buffer.slice!(0, ending + 6)
              @emit.call(Input::TextInput.new(value))
            elsif @buffer.start_with?("\e[", "\eO")
              sequence = @buffer.match(/\A\e[\[O]([\x30-\x3f]*)([\x20-\x2f]*)([\x40-\x7e])/n)
              raise Error, "terminal control sequence exceeds 1024 bytes" if !sequence && @buffer.bytesize > 1024
              break unless sequence
              if sequence[0] == "\e[M"
                break if @buffer.bytesize < 6
                button, x, y = @buffer.byteslice(3, 3).bytes.map { |value| value - 32 }
                @buffer.slice!(0, 6)
                mouse(button, x, y, (button & 3) == 3 ? "m" : "M")
              else
                @buffer.slice!(0, sequence[0].bytesize)
                control(sequence[1], sequence[2], sequence[3])
              end
            elsif @buffer.start_with?("\e]", "\eP", "\e_", "\e^")
              ending = @buffer.match(/(?:\a|\e\\)/n)
              raise Error, "terminal control string exceeds 64 KiB" if !ending && @buffer.bytesize > 65_536
              break unless ending
              @buffer.slice!(0, ending.end(0))
            else
              alt = @buffer.getbyte(0) == 27
              break if alt && @buffer.bytesize == 1
              start = alt ? 1 : 0
              byte = @buffer.getbyte(start)
              length = byte.between?(0xc2, 0xdf) ? 2 : byte.between?(0xe0, 0xef) ? 3 : byte.between?(0xf0, 0xf4) ? 4 : 1
              break if @buffer.bytesize < start + length
              value = @buffer.byteslice(start, length).force_encoding("UTF-8").scrub
              @buffer.slice!(0, start + length)
              character(value, alt ? ["alt"] : [])
            end
          end
          self
        end

        def flush_escape
          return false unless @buffer == "\e".b
          @buffer.clear
          key("esc")
          true
        end

        private

        def character(value, modifiers = [], held: false, released: false)
          byte = value.length == 1 ? value.ord : nil
          name = {0 => "ctrl-space", 8 => "backspace", 9 => "tab", 10 => "enter", 13 => "enter", 27 => "esc", 127 => "backspace"}[byte]
          name ||= "ctrl-#{(96 + byte).chr}" if byte && byte.between?(1, 26)
          name ||= {28 => "ctrl-\\", 29 => "ctrl-]", 30 => "ctrl-^", 31 => "ctrl-_"}[byte]
          if name || !modifiers.empty? || released
            key(name || value, modifiers, held: held, released: released)
          else
            @emit.call(Input::TextInput.new(value))
          end
        end

        def key(name, modifiers = [], held: false, released: false)
          stroke = (modifiers + [name]).join("-")
          stroke = Input::Keystroke.normalize(stroke) unless name == "-"
          @emit.call(released ? Input::KeyUp.new(stroke) : Input::KeyDown.new(stroke, held))
        end

        def modifiers(number)
          flags = [number - 1, 0].max
          [[4, "ctrl"], [2, "alt"], [1, "shift"], [8, "cmd"]].filter_map { |mask, name| name unless (flags & mask).zero? }
        end

        def control(parameters, intermediate, final)
          return unless intermediate.empty?
          if parameters.start_with?("<") && ["M", "m"].include?(final)
            numbers = parameters.delete_prefix("<").split(";")
            mouse(*numbers.map(&:to_i), final) if numbers.length == 3 && numbers.all? { |value| value.match?(/\A\d+\z/) }
            return
          end
          return unless parameters.match?(/\A[\d;:]*\z/)
          values = parameters.split(";")
          modifier, event = values.fetch(1, "1").split(":").map(&:to_i)
          mods = modifiers(modifier)
          if final == "u"
            codepoint = values.first.to_i
            return unless codepoint.between?(0, 0x10ffff) && !codepoint.between?(0xd800, 0xdfff)
            character(codepoint.chr("UTF-8"), mods, held: event == 2, released: event == 3)
          elsif final == "~" && values[0].to_i == 27 && values[2]
            codepoint = values[2].to_i
            character(codepoint.chr("UTF-8"), mods) if codepoint.between?(0, 0x10ffff) && !codepoint.between?(0xd800, 0xdfff)
          elsif (name = final == "~" ? TILDE_KEYS[values[0].to_i] : KEYS[final])
            mods |= ["shift"] if final == "Z"
            key(name, mods)
          end
        end

        def mouse(code, x, y, final)
          return unless code.between?(0, 255) && x.between?(1, 1_000_000) && y.between?(1, 1_000_000)
          position = Point.new((x - 0.5) * 8, (y - 0.5) * 20)
          mods = [[16, "ctrl"], [8, "alt"], [4, "shift"]].filter_map { |mask, name| name unless (code & mask).zero? }
          button = {0 => :left, 1 => :middle, 2 => :right}.fetch(code & 3, @pressed_button || :other)
          if (code & 64) != 0
            delta = [Point.new(0, -40), Point.new(0, 40), Point.new(-40, 0), Point.new(40, 0)][code & 3]
            @emit.call(Input::ScrollWheel.new(position, delta, :changed, mods))
          elsif final == "m"
            @emit.call(Input::MouseUp.new(position, button, mods))
            @pressed_button = nil
          elsif (code & 32) != 0
            @emit.call(Input::MouseMove.new(position, mods))
          else
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            clicks = @last_click && @last_click[0] == button && @last_click[1] == position && now - @last_click[2] < 0.4 ? 2 : 1
            @pressed_button, @last_click = button, [button, position, now]
            @emit.call(Input::MouseDown.new(position, button, mods, clicks))
          end
        end
      end
    end
  end
end
