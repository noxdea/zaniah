# frozen_string_literal: true

module Zaniah
  module Platform
    module Mac
      class NativeMenu
        MODIFIERS = {"ctrl" => 1 << 18, "alt" => 1 << 19, "shift" => 1 << 17, "cmd" => 1 << 20}.freeze
        KEYS = {"enter" => "\r", "tab" => "\t", "esc" => "\e", "backspace" => "\b",
                "delete" => "\x7f", "left" => "\uF702", "right" => "\uF703",
                "up" => "\uF700", "down" => "\uF701", "home" => "\uF729", "end" => "\uF72B"}.freeze

        attr_reader :root, :windows_menu

        def self.key_equivalent(shortcut)
          return ["", 0] if shortcut.nil? || shortcut.include?(" ")
          normalized = Input::Keystroke.normalize(shortcut)
          parts = if normalized == "-"
            ["-"]
          elsif normalized.end_with?("--")
            normalized[0...-2].split("-") + ["-"]
          else
            normalized.split("-")
          end
          key = parts.pop
          return ["", 0] unless key && (key.length == 1 || KEYS.key?(key))
          [KEYS.fetch(key, key), parts.sum { |part| MODIFIERS.fetch(part) }]
        rescue ArgumentError
          ["", 0]
        end

        def initialize(host, model, window)
          @host, @model, @window = host, model, window
          @actions, @dynamic, @next_tag = {}, {}, 0
          @root = menu
          items = model.resolve(registry: window.app.actions, keymap: window.dispatcher.keymap, platform: :mac)
          add_app_menu(@root)
          items.each do |item|
            next if item.role == :app_menu
            if item.role == :window_menu
              add_window_menu(@root)
            else
              add_item(@root, item)
            end
          end
        end

        def release = O.release(@root)

        def perform(tag)
          action = @actions[tag]
          window = @host.active_window || @window
          action && window && window.dispatcher.perform(action, source: :menu)
        end

        def validate(item)
          action = @actions[O.send(item, "tag", result: :long)]
          return true unless action
          window = @host.active_window || @window
          state = window&.dispatcher&.available?(action)
          O.send(item, "setState:", window&.dispatcher&.checked?(action) ? 1 : 0, args: [:long], result: :void)
          state == :enabled
        end

        def update(native_menu)
          if (item = @dynamic[native_menu])
            clear_menu(native_menu)
            populate(native_menu, @model.children_for(item, registry: @window.app.actions,
              keymap: @window.dispatcher.keymap, platform: :mac))
          end
          count = O.send(native_menu, "numberOfItems", result: :long)
          count.times do |index|
            child = O.send(native_menu, "itemAtIndex:", index, args: [:long])
            next if O.send(child, "isSeparatorItem", result: :bool) != 0
            O.send(child, "setEnabled:", validate(child) ? 1 : 0, args: [:bool], result: :void)
          end
        end

        private

        def menu(title = "")
          native = O.send(O.alloc("NSMenu"), "initWithTitle:", O.string(title), args: [:pointer])
          O.send(native, "setDelegate:", @host.delegate, args: [:pointer], result: :void)
          O.send(native, "setAutoenablesItems:", 0, args: [:bool], result: :void)
          native
        end

        def native_item(title, selector = nil, shortcut = nil)
          key, mask = self.class.key_equivalent(shortcut)
          item = O.send(O.alloc("NSMenuItem"), "initWithTitle:action:keyEquivalent:",
            O.string(title), selector ? O.selector(selector) : 0, O.string(key), args: [:pointer] * 3)
          O.send(item, "setKeyEquivalentModifierMask:", mask, args: [:ulong], result: :void) unless key.empty?
          item
        end

        def append(parent, item, submenu = nil)
          O.send(item, "setSubmenu:", submenu, args: [:pointer], result: :void) if submenu
          O.send(parent, "addItem:", item, args: [:pointer], result: :void)
          O.release(item)
          O.release(submenu) if submenu
        end

        def add_item(parent, item)
          if item.separator?
            O.send(parent, "addItem:", O.send(O.klass("NSMenuItem"), "separatorItem"), args: [:pointer], result: :void)
          elsif item.submenu?
            submenu = menu(item.title)
            @dynamic[submenu] = item if item.dynamic
            populate(submenu, @model.children_for(item, registry: @window.app.actions,
              keymap: @window.dispatcher.keymap, platform: :mac)) unless item.dynamic
            append(parent, native_item(item.title), submenu)
          else
            native = native_item(item.title, "zaniahMenuAction:", item.shortcut)
            @next_tag += 1
            @actions[@next_tag] = item.action
            O.send(native, "setTag:", @next_tag, args: [:long], result: :void)
            O.send(native, "setTarget:", @host.delegate, args: [:pointer], result: :void)
            append(parent, native)
          end
        end

        def populate(parent, items) = items.each { |item| add_item(parent, item) }

        def clear_menu(parent)
          count = O.send(parent, "numberOfItems", result: :long)
          count.times do |index|
            child = O.send(parent, "itemAtIndex:", index, args: [:long])
            @actions.delete(O.send(child, "tag", result: :long))
            submenu = O.send(child, "submenu")
            next if submenu.zero?
            @dynamic.delete(submenu)
            clear_menu(submenu)
          end
          O.send(parent, "removeAllItems", result: :void)
        end

        def add_app_menu(parent)
          process = O.send(O.klass("NSProcessInfo"), "processInfo")
          name = O.text(O.send(process, "processName"))
          submenu = menu(name)
          [["About #{name}", "orderFrontStandardAboutPanel:", nil], ["Hide #{name}", "hide:", "cmd-h"],
           ["Hide Others", "hideOtherApplications:", "cmd-alt-h"], ["Show All", "unhideAllApplications:", nil]].each do |title, selector, shortcut|
            item = native_item(title, selector, shortcut)
            O.send(item, "setTarget:", @host.handle, args: [:pointer], result: :void)
            append(submenu, item)
          end
          O.send(submenu, "addItem:", O.send(O.klass("NSMenuItem"), "separatorItem"), args: [:pointer], result: :void)
          quit = native_item("Quit #{name}", "terminate:", "cmd-q")
          O.send(quit, "setTarget:", @host.handle, args: [:pointer], result: :void)
          append(submenu, quit)
          append(parent, native_item(name), submenu)
        end

        def add_window_menu(parent)
          submenu = menu("Window")
          [["Minimize", "performMiniaturize:", "cmd-m"], ["Zoom", "performZoom:", nil],
           ["Bring All to Front", "arrangeInFront:", nil]].each do |title, selector, shortcut|
            item = native_item(title, selector, shortcut)
            O.send(item, "setTarget:", selector == "arrangeInFront:" ? @host.handle : @window.handle,
              args: [:pointer], result: :void)
            append(submenu, item)
          end
          @windows_menu = submenu
          append(parent, native_item("Window"), submenu)
        end
      end
    end
  end
end
