# frozen_string_literal: true

require "open3"

module Zaniah
  module Accessibility
    module Linux
      module_function

      def publish(_window, root, _changes)
        return unless root && ENV["DBUS_SESSION_BUS_ADDRESS"]
        _output, _error, status = Open3.capture3("gdbus", "emit", "--session",
          "--object-path", "/org/zaniah/Accessibility",
          "--signal", "org.a11y.atspi.Event.Object.ChildrenChanged")
        status.success?
      rescue Errno::ENOENT
        false
      end
    end
  end
end
