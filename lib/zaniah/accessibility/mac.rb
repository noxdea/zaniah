# frozen_string_literal: true

module Zaniah
  module Accessibility
    module Mac
      ROLES = {button: "AXButton", checkbox: "AXCheckBox", radio: "AXRadioButton",
        textbox: "AXTextField", searchbox: "AXTextField", dialog: "AXDialog",
        table: "AXTable", row: "AXRow", cell: "AXCell", slider: "AXSlider",
        link: "AXLink", image: "AXImage", heading: "AXHeading"}.freeze

      module_function

      def publish(window, root, _changes)
        return unless root && defined?(Platform::Mac::O) && window.respond_to?(:view)
        object = window.view
        Platform::Mac::O.send(object, "setAccessibilityElement:", 1, args: [:bool], result: :void)
        Platform::Mac::O.send(object, "setAccessibilityRole:", Platform::Mac::O.string(ROLES.fetch(root.role, "AXGroup")), args: [:pointer], result: :void)
        Platform::Mac::O.send(object, "setAccessibilityLabel:", Platform::Mac::O.string(root.label || "Zaniah application"), args: [:pointer], result: :void)
        notify = Platform::Mac::APPKIT.fn(:NSAccessibilityPostNotification,
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
        notify.call(object, Platform::Mac::O.string("AXLayoutChanged"))
      rescue Fiddle::DLError
        nil
      end
    end
  end
end
