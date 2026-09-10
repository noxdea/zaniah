# frozen_string_literal: true

require_relative "../../ffi/library"

module Zaniah
  module Platform
    module Windows
      # A native ConPTY process. Output is UTF-8 VT data, compatible with the
      # same terminal parser used by Unix PTYs. Empty means idle, nil means EOF.
      class Terminal
        P, I, U, N, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOID
        attr_reader :pid
        def initialize(command: nil, columns: 80, rows: 24, cwd: nil, env: {})
          raise Error, "ConPTY requires 64-bit Windows Ruby" unless Fiddle::SIZEOF_VOIDP == 8
          @kernel = FFI::Library.new("kernel32.dll")
          @output, @pending, @closed, @eof = Queue.new, "".b, false, false
          input_read, @input_write = pipe
          @output_read, output_write = pipe
          console = [0].pack("J")
          check_hresult(@kernel.fn(:CreatePseudoConsole, [I, P, P, U, P], I).call(coordinate(columns, rows), input_read, output_write, 0, console))
          @console = console.unpack1("J")
          size = [0].pack("J")
          @kernel.fn(:InitializeProcThreadAttributeList, [P, U, U, P], I).call(0, 1, 0, size)
          attributes = Fiddle::Pointer.malloc(size.unpack1("J"), Fiddle::RUBY_FREE)
          check(@kernel.fn(:InitializeProcThreadAttributeList, [P, U, U, P], I).call(attributes, 1, 0, size), "InitializeProcThreadAttributeList")
          check(@kernel.fn(:UpdateProcThreadAttribute, [P, U, N, P, N, P, P], I).call(attributes, 0, 0x20016, @console, 8, 0, 0), "UpdateProcThreadAttribute")
          startup = "\0".b * 112
          startup[0, 4] = [112].pack("I")
          startup[60, 4] = [0x100].pack("I") # STARTF_USESTDHANDLES
          startup[104, 8] = [attributes.to_i].pack("J")
          info = "\0".b * 24
          command ||= ENV.fetch("COMSPEC", "cmd.exe")
          line = command.is_a?(Array) ? command.map { |part| self.class.quote_argument(part.to_s) }.join(" ") : command.to_s
          line = wide(line)
          directory = cwd ? wide(File.expand_path(cwd)) : nil
          environment = env.empty? ? nil : (ENV.to_h.merge(env.transform_keys(&:to_s).transform_values(&:to_s)).sort_by { |key, _| key.downcase }.map { |key, value| "#{key}=#{value}\0" }.join + "\0").encode("UTF-16LE").b
          check(@kernel.fn(:CreateProcessW, [P, P, P, P, I, U, P, P, P, P], I).call(0, line, 0, 0, 0, 0x00080400, environment || 0, directory || 0, startup, info), "CreateProcessW")
          close_handle(input_read)
          close_handle(output_write)
          input_read = output_write = nil
          @process, thread, @pid = info.unpack("JJI")
          close_handle(thread)
          @reader = Thread.new do
            loop do
              bytes, count = "\0".b * 65_536, [0].pack("I")
              ok = @kernel.fn(:ReadFile, [P, P, U, P, P], I, need_gvl: false).call(@output_read, bytes, bytes.bytesize, count, 0)
              break if ok.zero? || count.unpack1("I").zero?
              @output << bytes.byteslice(0, count.unpack1("I"))
            end
          ensure
            @output << nil
          end
        ensure
          @kernel.fn(:DeleteProcThreadAttributeList, [P], V).call(attributes) if attributes
          close_handle(input_read) if input_read
          close_handle(output_write) if output_write
        end

        # CommandLineToArgvW/CRT escaping: backslashes before quotes and the
        # closing delimiter must be doubled; other backslashes are literal.
        def self.quote_argument(value)
          return value unless value.empty? || value.match?(/[\s"]/)
          '"' + value.gsub(/(\\*)"/) { Regexp.last_match(1) * 2 + '\\"' }.sub(/(\\+)\z/) { Regexp.last_match(1) * 2 } + '"'
        end
        def wide(text) = text.encode("UTF-16LE").b + "\0\0"
        def coordinate(columns, rows)
          raise ArgumentError, "invalid terminal size" unless columns.between?(1, 32_767) && rows.between?(1, 32_767)
          [columns, rows].pack("s2").unpack1("l")
        end
        def pipe
          read_handle, write_handle = [0].pack("J"), [0].pack("J")
          check(@kernel.fn(:CreatePipe, [P, P, P, U], I).call(read_handle, write_handle, 0, 0), "CreatePipe")
          [read_handle.unpack1("J"), write_handle.unpack1("J")]
        end
        def read_available(limit: 65_536)
          raise ArgumentError, "limit must be positive" unless limit.positive?
          until @output.empty?
            bytes = @output.pop
            if bytes.nil?
              @eof = true
              break
            end
            @pending << bytes
          end
          return nil if @pending.empty? && @eof
          @pending.slice!(0, limit)
        end
        def write(bytes)
          raise IOError, "terminal closed" if @closed
          offset = 0
          while offset < bytes.bytesize
            chunk = bytes.byteslice(offset, bytes.bytesize - offset)
            count = [0].pack("I")
            check(@kernel.fn(:WriteFile, [P, P, U, P, P], I, need_gvl: false).call(@input_write, chunk, chunk.bytesize, count, 0), "WriteFile")
            written = count.unpack1("I")
            raise IOError, "ConPTY write made no progress" if written.zero?
            offset += written
          end
          offset
        end
        def resize(columns, rows)
          check_hresult(@kernel.fn(:ResizePseudoConsole, [P, I], I).call(@console, coordinate(columns, rows)))
        end
        def alive? = !@closed && @kernel.fn(:WaitForSingleObject, [P, U], U).call(@process, 0) == 258
        def close
          return if @closed
          @closed = true
          close_handle(@input_write)
          # ReadFile releases the GVL so the reader drains ConPTY while closing.
          @kernel.fn(:ClosePseudoConsole, [P], V, need_gvl: false).call(@console)
          @reader.join(2)
          close_handle(@output_read)
          close_handle(@process)
        end
        def close_handle(handle) = @kernel.fn(:CloseHandle, [P], I).call(handle)
        def check(result, name)
          raise SystemCallError.new(name, Fiddle.last_error) if result.zero?
          result
        end
        def check_hresult(result)
          raise Error, "ConPTY failure 0x#{(result & 0xffffffff).to_s(16)}" unless (result & 0x80000000).zero?
          result
        end
      end
    end
  end
end
