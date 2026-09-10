# frozen_string_literal: true

require_relative "../../ffi/library"
require_relative "../file_event"

module Zaniah
  module Platform
    module Windows
      class Watcher
        P, I, U, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOID
        def initialize(paths, latency: 0.05)
          @kernel, @handles, @closed = FFI::Library.new("kernel32.dll"), [], false
          paths = Array(paths).map { |path| File.expand_path(path) }
          raise ArgumentError, "watch paths required" if paths.empty?
          paths.map { |path| File.directory?(path) ? path : File.dirname(path) }.uniq.each do |path|
            handle = @kernel.fn(:CreateFileW, [P, U, U, P, U, U, P], P).call(path.encode("UTF-16LE").b + "\0\0", 1, 7, 0, 3, 0x42000000, 0)
            raise SystemCallError.new("CreateFileW #{path}", Fiddle.last_error) if handle.to_i == -1 || handle.to_i == (1 << 64) - 1
            event = @kernel.fn(:CreateEventW, [P, I, I, P], P).call(0, 1, 0, 0)
            raise Error, "CreateEventW failed" if event.null?
            overlapped = Fiddle::Pointer.malloc(32, Fiddle::RUBY_FREE)
            overlapped[0, 32] = "\0" * 32
            overlapped[24, 8] = [event.to_i].pack("J")
            entry = [path, handle, event, overlapped, Fiddle::Pointer.malloc(65_536, Fiddle::RUBY_FREE)]
            @handles << entry
            issue(entry)
          end
        end
        def issue(entry)
          _, handle, event, overlapped, buffer = entry
          @kernel.fn(:ResetEvent, [P], I).call(event)
          ok = @kernel.fn(:ReadDirectoryChangesW, [P, P, U, I, U, P, P, P], I).call(handle, buffer, 65_536, 1, 0x17f, 0, overlapped, 0)
          raise SystemCallError.new("ReadDirectoryChangesW", Fiddle.last_error) if ok.zero? && Fiddle.last_error != 997
        end
        def poll(timeout: 0)
          return [] if @closed
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          events = []
          loop do
            @handles.each do |entry|
              root, handle, event, overlapped, buffer = entry
              next unless @kernel.fn(:WaitForSingleObject, [P, U], U).call(event, 0).zero?
              count = [0].pack("I")
              ok = @kernel.fn(:GetOverlappedResult, [P, P, P, I], I).call(handle, overlapped, count, 0)
              size = count.unpack1("I")
              if ok.zero? || size.zero?
                events << FileEvent.new(:overflow, root, nil)
              else
                offset, old_path = 0, nil
                loop do
                  following, action, length = buffer[offset, 12].unpack("I3")
                  break if offset + 12 + length > size
                  name = buffer[offset + 12, length].force_encoding("UTF-16LE").encode("UTF-8")
                  path = File.join(root, name.tr("\\", "/"))
                  if action == 4
                    old_path = path
                  else
                    kind = {1 => :created, 2 => :deleted, 3 => :modified, 5 => :renamed}.fetch(action, :modified)
                    events << FileEvent.new(kind, path, action == 5 ? old_path : nil)
                    old_path = nil
                  end
                  break if following.zero?
                  offset += following
                end
              end
              issue(entry)
            end
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if !events.empty? || remaining <= 0
            # Wait on groups supported by Win32 instead of starting Ruby watcher threads.
            @handles.each_slice(64) do |entries|
              handles = entries.map { |entry| entry[2].to_i }.pack("J*")
              @kernel.fn(:WaitForMultipleObjects, [U, P, I, U], U).call(entries.length, handles, 0, [(remaining * 1000).ceil, 50].min)
            end
          end
          events.uniq
        end
        def close
          return if @closed
          @closed = true
          @handles.each do |_, handle, event, overlapped, _|
            @kernel.fn(:CancelIoEx, [P, P], I).call(handle, overlapped)
            @kernel.fn(:GetOverlappedResult, [P, P, P, I], I, need_gvl: false).call(handle, overlapped, [0].pack("I"), 1)
            @kernel.fn(:CloseHandle, [P], I).call(handle)
            @kernel.fn(:CloseHandle, [P], I).call(event)
          end
          @handles.clear
        end
      end
    end
  end
end
