# frozen_string_literal: true

module Zaniah
  module Accessibility
    module Windows
      EVENT_OBJECT_REORDER = 0x8004
      OBJID_CLIENT = -4
      CHILDID_SELF = 0

      module_function

      def publish(window, root, _changes)
        return unless root && window.respond_to?(:handle)
        user = window.instance_variable_get(:@user)
        return unless user
        user.fn(:NotifyWinEvent,
          [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
          .call(EVENT_OBJECT_REORDER, window.handle, OBJID_CLIENT, CHILDID_SELF)
      rescue Fiddle::DLError
        nil
      end
    end
  end
end
