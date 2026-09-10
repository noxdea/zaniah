# frozen_string_literal: true

require_relative "../../ffi/library"
require_relative "../file_event"

module Zaniah
  module Platform
    module Linux
      class Watcher
        I, P = Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP
        def initialize(paths, latency: 0.05)
          @lib = FFI::Library.new(nil)
          fd = @lib.fn(:inotify_init1, [I], I).call(0x800 | 0x80000)
          raise SystemCallError.new("inotify_init1", Fiddle.last_error) if fd.negative?
          @io, @directories, @moves, @closed = IO.for_fd(fd), {}, {}, false
          paths = Array(paths).map { |path| File.expand_path(path) }
          raise ArgumentError, "watch paths required" if paths.empty?
          paths.each { |path| add_tree(File.directory?(path) ? path : File.dirname(path)) }
        end
        def add_tree(path)
          ([path] + Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).select { |entry| File.basename(entry) != "." && File.directory?(entry) && !File.symlink?(entry) }).each do |directory|
            descriptor = @lib.fn(:inotify_add_watch, [I, P, I], I).call(@io.fileno, directory, 0x00000fff)
            raise SystemCallError.new("inotify_add_watch #{directory}", Fiddle.last_error) if descriptor.negative?
            @directories[descriptor] = directory
          end
        end
        def poll(timeout: 0)
          return [] if @closed || !IO.select([@io], nil, nil, timeout)
          events = []
          while (bytes = @io.read_nonblock(65_536, exception: false)).is_a?(String)
            offset = 0
            while offset + 16 <= bytes.bytesize
              descriptor, mask, cookie, length = bytes.byteslice(offset, 16).unpack("iIII")
              name = bytes.byteslice(offset + 16, length).split("\0", 2).first.to_s
              offset += 16 + length
              if (mask & 0x4000) != 0
                events << FileEvent.new(:overflow, nil, nil)
                next
              end
              directory = @directories[descriptor]
              next unless directory
              path = name.empty? ? directory : File.join(directory, name)
              if (mask & 0x8000) != 0
                @directories.delete(descriptor)
              elsif (mask & 0x40) != 0
                @moves[cookie] = path
                events << FileEvent.new(:deleted, path, nil)
              elsif (mask & 0x80) != 0
                old = @moves.delete(cookie)
                events << FileEvent.new(old ? :renamed : :created, path, old)
              elsif (mask & 0x300) != 0
                events << FileEvent.new((mask & 0x200) != 0 ? :deleted : :created, path, nil)
              elsif (mask & (2 | 4 | 8 | 0x400 | 0x800)) != 0
                events << FileEvent.new(:modified, path, nil)
              end
              add_tree(path) if (mask & 0x40000000) != 0 && (mask & 0x180) != 0 && File.directory?(path)
            end
          end
          @moves.clear
          events.uniq
        end
        def close
          return if @closed
          @closed = true
          @io.close
        end
      end
    end
  end
end
