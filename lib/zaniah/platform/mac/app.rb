# frozen_string_literal: true

module Zaniah
  module Platform
    module Mac
      class App
        EVENT_MASK = (1 << 64) - 1
        EVENT_ARGUMENTS = [:ulong, :pointer, :pointer, :bool].freeze
        POINTER_ARGUMENT = [:pointer].freeze
        WAIT_ARGUMENT = [:double].freeze

        attr_reader :handle
        def self.instance = @instance ||= new
        def initialize
          raise Error, "Cocoa must run on the main Ruby thread" unless Thread.current == Thread.main
          @handle = O.send(O.klass("NSApplication"), "sharedApplication")
          @run_loop_mode = O.send(O.string("kCFRunLoopDefaultMode"), "retain")
          O.subclass("ZaniahApplicationDelegate", "NSObject", protocols: ["NSApplicationDelegate"]) do |klass|
            O.method(klass, "applicationShouldTerminate:", args: [:pointer], result: :ulong, encoding: "Q@:@") do |_delegate, _, _application|
              WINDOWS.values.uniq.each { |window| break unless window.close }
              # Ruby's window loop owns shutdown and ensures; Cocoa must not exit
              # the process before close handlers have checked unsaved buffers.
              0
            end
          end
          @delegate = O.new("ZaniahApplicationDelegate")
          O.send(@handle, "setDelegate:", @delegate, args: [:pointer], result: :void)
          O.send(@handle, "setActivationPolicy:", 0, args: [:long], result: :bool)
          menu, item, submenu = O.new("NSMenu"), O.new("NSMenuItem"), O.new("NSMenu")
          quit = O.send(O.alloc("NSMenuItem"), "initWithTitle:action:keyEquivalent:", O.string("Quit"), O.selector("terminate:"), O.string("q"), args: [:pointer] * 3)
          O.send(submenu, "addItem:", quit, args: [:pointer], result: :void)
          O.send(item, "setSubmenu:", submenu, args: [:pointer], result: :void)
          O.send(menu, "addItem:", item, args: [:pointer], result: :void)
          O.send(@handle, "setMainMenu:", menu, args: [:pointer], result: :void)
          [quit, submenu, item, menu].each { |object| O.release(object) }
          O.send(@handle, "finishLaunching", result: :void)
          O.send(@handle, "activateIgnoringOtherApps:", 1, args: [:bool], result: :void)
        end

        def poll(wait: 0)
          pool = O.new("NSAutoreleasePool")
          # Cocoa treats a nil deadline as distantPast: drain queued events
          # without allocating an NSDate for each nonblocking poll.
          deadline = wait.zero? ? 0 : O.send(O.klass("NSDate"), "dateWithTimeIntervalSinceNow:", wait, args: WAIT_ARGUMENT)
          loop do
            event = O.send(@handle, "nextEventMatchingMask:untilDate:inMode:dequeue:", EVENT_MASK,
                           deadline, @run_loop_mode, 1, args: EVENT_ARGUMENTS)
            break if event.zero?
            O.send(@handle, "sendEvent:", event, args: POINTER_ARGUMENT, result: :void)
            deadline = 0
          end
          O.send(@handle, "updateWindows", result: :void)
        ensure
          O.release(pool) if pool
        end

        def run
          yield self if block_given?
          until WINDOWS.values.uniq.all?(&:closed?)
            poll(wait: WINDOWS.values.any?(&:dirty?) ? 0 : 0.05)
            WINDOWS.values.uniq.each { |window| window.tick(poll_events: false) }
          end
        end
      end
    end
  end
end
