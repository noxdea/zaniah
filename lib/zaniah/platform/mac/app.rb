# frozen_string_literal: true

require_relative "native_menu"

module Zaniah
  module Platform
    module Mac
      class App
        EVENT_MASK = (1 << 64) - 1
        EVENT_ARGUMENTS = [:ulong, :pointer, :pointer, :bool].freeze
        POINTER_ARGUMENT = [:pointer].freeze
        WAIT_ARGUMENT = [:double].freeze

        attr_reader :handle, :delegate
        def self.instance = @instance ||= new
        def initialize
          raise Error, "Cocoa must run on the main Ruby thread" unless Thread.current == Thread.main
          @handle = O.send(O.klass("NSApplication"), "sharedApplication")
          @run_loop_mode = O.send(O.string("kCFRunLoopDefaultMode"), "retain")
          O.subclass("ZaniahApplicationDelegate", "NSObject", protocols: ["NSApplicationDelegate", "NSMenuDelegate"]) do |klass|
            O.method(klass, "applicationShouldTerminate:", args: [:pointer], result: :ulong, encoding: "Q@:@") do |_delegate, _, _application|
              WINDOWS.values.uniq.each { |window| break unless window.close }
              # Ruby's window loop owns shutdown and ensures; Cocoa must not exit
              # the process before close handlers have checked unsaved buffers.
              0
            end
            O.method(klass, "zaniahMenuAction:", args: [:pointer], encoding: "v@:@") do |_delegate, _, item|
              App.instance.native_callback { App.instance.menu_action(O.send(item, "tag", result: :long)) }
            end
            O.method(klass, "validateMenuItem:", args: [:pointer], result: :bool, encoding: "B@:@") do |_delegate, _, item|
              App.instance.native_callback { App.instance.validate_menu_item(item) } ? 1 : 0
            end
            O.method(klass, "menuNeedsUpdate:", args: [:pointer], encoding: "v@:@") do |_delegate, _, menu|
              App.instance.native_callback { App.instance.update_menu(menu) }
            end
          end
          @delegate = O.new("ZaniahApplicationDelegate")
          O.send(@handle, "setDelegate:", @delegate, args: [:pointer], result: :void)
          O.send(@handle, "setActivationPolicy:", 0, args: [:long], result: :bool)
          install_default_menu
          @menu_identity = [nil, nil, nil]
          O.send(@handle, "finishLaunching", result: :void)
          O.send(@handle, "activateIgnoringOtherApps:", 1, args: [:bool], result: :void)
        end

        def install_default_menu
          menu, item, submenu = O.new("NSMenu"), O.new("NSMenuItem"), O.new("NSMenu")
          quit = O.send(O.alloc("NSMenuItem"), "initWithTitle:action:keyEquivalent:", O.string("Quit"), O.selector("terminate:"), O.string("q"), args: [:pointer] * 3)
          O.send(submenu, "addItem:", quit, args: [:pointer], result: :void)
          O.send(item, "setSubmenu:", submenu, args: [:pointer], result: :void)
          O.send(menu, "addItem:", item, args: [:pointer], result: :void)
          O.send(@handle, "setMainMenu:", menu, args: [:pointer], result: :void)
          [quit, submenu, item, menu].each { |object| O.release(object) }
        end

        def active_window
          key = O.send(@handle, "keyWindow")
          main = O.send(@handle, "mainWindow") if key.zero?
          WINDOWS[key] || WINDOWS[main] || WINDOWS.values.uniq.reverse.find { |window| !window.closed? }
        end

        def sync_main_menu
          window = active_window
          model = window&.app&.menu_bar
          identity = [window&.object_id, model&.object_id, window&.dispatcher&.keymap&.object_id]
          return if identity == @menu_identity

          previous = @native_menu
          @native_menu = model && NativeMenu.new(self, model, window)
          O.send(@handle, "setWindowsMenu:", 0, args: [:pointer], result: :void)
          if @native_menu
            O.send(@handle, "setMainMenu:", @native_menu.root, args: [:pointer], result: :void)
            O.send(@handle, "setWindowsMenu:", @native_menu.windows_menu, args: [:pointer], result: :void) if @native_menu.windows_menu
          else
            install_default_menu
          end
          previous&.release
          @menu_identity = identity
        end

        def menu_action(tag) = @native_menu&.perform(tag)
        def validate_menu_item(item) = @native_menu&.validate(item) || false
        def update_menu(menu) = @native_menu&.update(menu)
        def native_callback
          yield
        rescue StandardError => error
          @native_error = error
          false
        end

        def poll(wait: 0)
          pool = O.new("NSAutoreleasePool")
          sync_main_menu
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
          sync_main_menu
          O.send(@handle, "updateWindows", result: :void)
          error, @native_error = @native_error, nil
          raise error if error
        ensure
          O.release(pool) if pool
        end

        def run
          yield self if block_given?
          until WINDOWS.values.uniq.all?(&:closed?)
            poll(wait: WINDOWS.values.any? { |window| window.dirty? || window.animation_active? } ? 0 : 0.05)
            WINDOWS.values.uniq.each { |window| window.tick(poll_events: false) }
          end
        end
      end
    end
  end
end
