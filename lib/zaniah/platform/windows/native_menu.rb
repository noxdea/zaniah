# frozen_string_literal: true

require "fiddle"

module Zaniah
  module Platform
    module Windows
      # Win32 menu handles belong to a window. Input shortcuts remain owned by Keymap.
      class NativeMenu
        FIRST_ID = 0x8000
        LAST_ID = 0xbfff
        POPUP = 0x0010
        SEPARATOR = 0x0800
        GRAYED = 0x0001
        CHECKED = 0x0008
        BY_POSITION = 0x0400

        def initialize(window, user)
          @window, @user = window, user
          @model, @root = nil, nil
          @entries, @actions = {}, {}
        end

        def sync(model)
          return if model.equal?(@model)
          close
          return unless model

          @root = create(:CreateMenu)
          @model = model
          append_items(@root, model.resolve(**resolve_options))
          raise Error, "SetMenu failed" if win(:SetMenu, [ptr, ptr], int, @window.handle, @root).zero?
          win(:DrawMenuBar, [ptr], int, @window.handle)
        rescue StandardError
          close
          raise
        end

        def command(wparam, lparam)
          return false unless lparam.zero? && (wparam >> 16).zero?
          action = @actions[wparam & 0xffff]
          return false unless action

          @window.dispatcher.perform(action, source: :menu)
          true
        end

        def prepare(popup, lparam)
          return false unless (lparam >> 16).zero?
          entry = @entries[popup.to_i]
          return false unless entry

          if entry[:item]&.dynamic
            clear_items(popup)
            append_items(popup, @model.children_for(entry[:item], **resolve_options))
          end
          entry[:children].each do |child|
            next unless child[:id]
            state = @window.dispatcher.available?(child[:item].action)
            win(:EnableMenuItem, [ptr, uint, uint], uint, popup, child[:id], state == :enabled ? 0 : GRAYED)
            checked = @window.dispatcher.checked?(child[:item].action)
            win(:CheckMenuItem, [ptr, uint, uint], uint, popup, child[:id], checked ? CHECKED : 0)
          end
          win(:DrawMenuBar, [ptr], int, @window.handle)
          true
        end

        def close
          return unless @root
          win(:SetMenu, [ptr, ptr], int, @window.handle, 0)
          win(:DestroyMenu, [ptr], int, @root)
          win(:DrawMenuBar, [ptr], int, @window.handle)
          @model, @root = nil, nil
          @entries.clear
          @actions.clear
        end

        private

        def ptr = Fiddle::TYPE_VOIDP
        def int = Fiddle::TYPE_INT
        def uint = Fiddle::TYPE_UINT

        def win(name, args, result, *values) = @user.fn(name, args, result).call(*values)

        def create(name)
          handle = win(name, [], ptr)
          raise Error, "#{name} failed" if handle.null?
          handle
        end

        def resolve_options
          {registry: @window.app.actions, keymap: @window.dispatcher.keymap, platform: :windows}
        end

        def append_items(menu, items)
          entry = (@entries[menu.to_i] ||= {item: nil, children: []})
          items.each do |item|
            if item.separator?
              append(menu, SEPARATOR, 0, nil)
              entry[:children] << {item: item}
            elsif item.submenu?
              child = create(:CreatePopupMenu)
              begin
                append(menu, POPUP, child.to_i, item.title)
              rescue StandardError
                win(:DestroyMenu, [ptr], int, child)
                raise
              end
              entry[:children] << {item: item, submenu: child}
              @entries[child.to_i] = {item: item, children: []}
              if item.dynamic
                append(child, GRAYED, 0, "") # Keep an unopened dynamic submenu expandable.
                @entries[child.to_i][:children] << {item: nil}
              else
                append_items(child, @model.children_for(item, **resolve_options))
              end
            else
              id = (FIRST_ID..LAST_ID).find { |candidate| !@actions.key?(candidate) }
              raise Error, "too many native menu items" unless id
              label = item.title.to_s.gsub("&", "&&")
              label += "\t#{shortcut_label(item.shortcut)}" if item.shortcut && !item.shortcut.include?(" ")
              append(menu, 0, id, label)
              @actions[id] = item.action
              entry[:children] << {item: item, id: id}
            end
          end
        end

        def append(menu, flags, id, label)
          text = label && @window.wide(label)
          raise Error, "AppendMenuW failed" if win(:AppendMenuW, [ptr, uint, Fiddle::TYPE_INTPTR_T, ptr], int, menu, flags, id, text || 0).zero?
        end

        def clear_items(menu)
          entry = @entries.fetch(menu.to_i)
          entry[:children].each do |child|
            @actions.delete(child[:id]) if child[:id]
            forget_submenu(child[:submenu]) if child[:submenu]
          end
          entry[:children].length.times do
            raise Error, "DeleteMenu failed" if win(:DeleteMenu, [ptr, uint, uint], int, menu, 0, BY_POSITION).zero?
          end
          entry[:children].clear
        end

        def forget_submenu(handle)
          @entries.delete(handle.to_i)&.fetch(:children)&.each do |child|
            @actions.delete(child[:id]) if child[:id]
            forget_submenu(child[:submenu]) if child[:submenu]
          end
        end

        def shortcut_label(shortcut)
          parts = shortcut.end_with?("--") ? shortcut.delete_suffix("--").split("-") + ["-"] : shortcut.split("-")
          parts.map do |part|
            {"ctrl" => "Ctrl", "alt" => "Alt", "shift" => "Shift", "cmd" => "Win",
             "esc" => "Esc", "enter" => "Enter", "space" => "Space", "left" => "Left",
             "right" => "Right", "up" => "Up", "down" => "Down"}.fetch(part, part.upcase)
          end.join("+")
        end
      end
    end
  end
end
