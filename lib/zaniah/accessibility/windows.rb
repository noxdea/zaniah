# frozen_string_literal: true

require_relative "windows/provider"

module Zaniah
  module Accessibility
    module Windows
      EVENT_OBJECT_REORDER = 0x8004
      AUTOMATION_EVENTS = {structure: 20_002, property: 20_004, focus: 20_005,
        layout: 20_008, announcement: 20_024}.freeze
      OBJID_CLIENT = -4
      CHILDID_SELF = 0

      module_function

      def publish(window, root, _changes)
        return unless root && window.respond_to?(:handle)
        bridge = bridges[window.handle.to_i] ||= Provider::Bridge.new(window)
        bridge.update(root)
        bridge.raise_events(window.accessibility_tree.events)
        user = window.instance_variable_get(:@user)
        return unless user
        user.fn(:NotifyWinEvent,
          [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
          .call(EVENT_OBJECT_REORDER, window.handle, OBJID_CLIENT, CHILDID_SELF)
      rescue Fiddle::DLError
        nil
      end

      def provider_result(window, wparam, lparam)
        return unless (lparam.to_i & 0xffffffff) == 0xffffffe7
        bridge = bridges[window.handle.to_i]
        return unless bridge&.root_provider
        bridge.return_provider(wparam, lparam)
      end

      def close(window) = bridges.delete(window.handle.to_i)
      def event_ids(events) = events.filter_map { |event| AUTOMATION_EVENTS[event.kind] }
      def bridges = (@bridges ||= {})
    end
  end
end
