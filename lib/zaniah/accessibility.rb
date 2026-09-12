# frozen_string_literal: true

require_relative "accessibility/node"
require_relative "accessibility/tree"
require_relative "accessibility/native_tree"
require_relative "accessibility/mac"
require_relative "accessibility/windows"
require_relative "accessibility/linux"

module Zaniah
  module Accessibility
    module_function

    def publish(window, root, changes)
      adapter = case window.class.name
      when /::Mac::/ then Mac
      when /::Windows::/ then Windows
      when /::Linux::/ then Linux
      end
      adapter&.publish(window, root, changes)
    end

    def poll(window)
      Linux.poll(window) if window.class.name.match?(/::Linux::/)
    end

    def close(window)
      case window.class.name
      when /::Mac::/ then Mac.close(window)
      when /::Windows::/ then Windows.close(window)
      when /::Linux::/ then Linux.close(window)
      end
    end

    def perform(window, node, action, bounds: node&.bounds)
      return false unless node && node.actions.include?(action)
      if action == :dismiss
        window.input(Input::KeyDown.new("esc", false))
        return true
      end
      return false unless bounds
      position = Point.new(bounds.x + bounds.width / 2.0, bounds.y + bounds.height / 2.0)
      if %i[increment decrement].include?(action)
        focus_at(window, position)
        window.dispatcher.key(action == :increment ? "right" : "left")
      else
        window.input(Input::MouseDown.new(position, :left, [], 1))
        window.input(Input::MouseUp.new(position, :left, []))
      end
      true
    end

    def focus_at(window, position)
      hit = window.dispatcher.hits.reverse.find { |candidate| candidate.bounds&.contains?(position) }
      owner = hit&.owner
      owner = owner.parent while owner && !owner.respond_to?(:focus_handle)
      handle = owner&.focus_handle
      window.dispatcher.focus(handle, origin: :programmatic) if handle
      !handle.nil?
    end
  end
end
