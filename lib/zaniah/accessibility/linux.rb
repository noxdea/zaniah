# frozen_string_literal: true

require "open3"
require_relative "linux/service"

module Zaniah
  module Accessibility
    module Linux
      module_function

      def publish(window, root, _changes)
        return false unless root
        service = services[window.object_id] ||= Service.new(window)
        service.update(root)
      rescue Fiddle::DLError, Errno::ENOENT, Error
        false
      end
      def poll(window) = services[window.object_id]&.poll
      def close(window) = services.delete(window.object_id)&.close
      def services = (@services ||= {})
    end
  end
end
