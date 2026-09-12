# frozen_string_literal: true

require_relative "accessibility/node"
require_relative "accessibility/tree"
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
  end
end
