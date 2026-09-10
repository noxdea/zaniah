# frozen_string_literal: true

require_relative "../../ffi/library"
require_relative "../file_event"

module Zaniah
  module Platform
    module Mac
      class Watcher
        P, I, L, D, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_VOID
        def initialize(paths, latency: 0.05)
          @cf = FFI::Library.new("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
          @fs = FFI::Library.new("/System/Library/Frameworks/CoreServices.framework/CoreServices")
          @events, @closed = [], false
          @thread = Thread.current
          paths = Array(paths).map { |path| File.expand_path(path) }
          raise ArgumentError, "watch paths required" if paths.empty?
          strings = paths.map do |path|
            @cf.fn(:CFStringCreateWithCString, [P, P, I], P).call(0, path, 0x08000100)
          end
          pointers = strings.map(&:to_i).pack("J*")
          array = @cf.fn(:CFArrayCreate, [P, P, Fiddle::TYPE_LONG, P], P).call(0, pointers, strings.length, @cf.handle["kCFTypeArrayCallBacks"])
          @callback = Fiddle::Closure::BlockCaller.new(V, [P, P, Fiddle::TYPE_SIZE_T, P, P, P]) do |_stream, _info, count, native_paths, flags, _ids|
            count.times do |index|
              address = Fiddle::Pointer.new(native_paths)[index * Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_VOIDP].unpack1("J")
              path = Fiddle::Pointer.new(address).to_s.force_encoding("UTF-8")
              mask = Fiddle::Pointer.new(flags)[index * 4, 4].unpack1("I")
              kind = if (mask & 0x7) != 0 then :overflow
              elsif (mask & 0x200) != 0 then :deleted
              elsif (mask & 0x100) != 0 then :created
              else :modified
              end
              @events << FileEvent.new(kind, path, nil)
            end
          end
          @stream = @fs.fn(:FSEventStreamCreate, [P, P, P, P, L, D, I], P).call(0, @callback, 0, array, -1, latency, 0x16)
          raise Error, "FSEventStreamCreate failed" if @stream.null?
          @loop = @cf.fn(:CFRunLoopGetCurrent, [], P).call
          @mode = Fiddle::Pointer.new(@cf.handle["kCFRunLoopDefaultMode"])[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
          @fs.fn(:FSEventStreamScheduleWithRunLoop, [P, P, P], V).call(@stream, @loop, @mode)
          raise Error, "FSEventStreamStart failed" if @fs.fn(:FSEventStreamStart, [P], Fiddle::TYPE_BOOL).call(@stream) == 0
        ensure
          strings&.each { |string| @cf.fn(:CFRelease, [P], V).call(string) }
          @cf.fn(:CFRelease, [P], V).call(array) if array
        end
        def poll(timeout: 0)
          return [] if @closed
          raise Error, "FSEvents must be polled on its creating thread" unless Thread.current == @thread
          @cf.fn(:CFRunLoopRunInMode, [P, D, Fiddle::TYPE_BOOL], I).call(@mode, timeout, 1)
          events, @events = @events, []
          events
        end
        def close
          return if @closed
          @closed = true
          @fs.fn(:FSEventStreamStop, [P], V).call(@stream)
          @fs.fn(:FSEventStreamInvalidate, [P], V).call(@stream)
          @fs.fn(:FSEventStreamRelease, [P], V).call(@stream)
        end
      end
    end
  end
end
