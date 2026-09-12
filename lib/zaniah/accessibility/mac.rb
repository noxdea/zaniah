# frozen_string_literal: true

module Zaniah
  module Accessibility
    module Mac
      ELEMENTS = {}
      ROLES = {
        button: "AXButton", checkbox: "AXCheckBox", radio: "AXRadioButton", switch: "AXCheckBox",
        textbox: "AXTextField", searchbox: "AXTextField", combobox: "AXComboBox", listbox: "AXList",
        dialog: "AXDialog", table: "AXTable", row: "AXRow", cell: "AXCell", columnheader: "AXButton",
        tree: "AXOutline", treeitem: "AXRow", list: "AXList", listitem: "AXRow", slider: "AXSlider",
        progressbar: "AXProgressIndicator", meter: "AXLevelIndicator", link: "AXLink", image: "AXImage",
        heading: "AXHeading", text: "AXStaticText", separator: "AXSplitter", toolbar: "AXToolbar",
        menubar: "AXMenuBar", menu: "AXMenu", menuitem: "AXMenuItem", tab: "AXRadioButton",
        tabpanel: "AXGroup", tooltip: "AXHelpTag", status: "AXStaticText", navigation: "AXGroup",
        radiogroup: "AXRadioGroup", form: "AXGroup", group: "AXGroup"
      }.freeze
      NATIVE_ACTIONS = {
        "AXPress" => %i[press toggle select sort expand collapse],
        "AXIncrement" => %i[increment],
        "AXDecrement" => %i[decrement],
        "AXCancel" => %i[dismiss]
      }.freeze

      module_function

      def publish(window, root, _changes)
        return unless root && defined?(Platform::Mac::O) && window.respond_to?(:view)
        install
        ELEMENTS.delete_if { |_element, (owner, _node)| owner.equal?(window) }
        tree = NativeTree.new(root)
        children = mutable_array
        append(children, native_element(window, tree, tree.root, window.view))
        object = window.view
        Platform::Mac::O.send(object, "setAccessibilityElement:", 1, args: [:bool], result: :void)
        Platform::Mac::O.send(object, "setAccessibilityRole:", Platform::Mac::O.string("AXGroup"), args: [:pointer], result: :void)
        Platform::Mac::O.send(object, "setAccessibilityLabel:", Platform::Mac::O.string("Zaniah application"), args: [:pointer], result: :void)
        Platform::Mac::O.send(object, "setAccessibilityChildren:", children, args: [:pointer], result: :void)
        window.instance_variable_set(:@native_accessibility_tree, tree)
        window.instance_variable_set(:@native_accessibility_children, children)
        notify(window, object)
      rescue Fiddle::DLError
        nil
      end

      def install
        return if @installed
        Platform::Mac::O.subclass("ZaniahAccessibilityElement", "NSAccessibilityElement") do |klass|
          Platform::Mac::O.method(klass, "accessibilityActionNames", result: :pointer, encoding: "@@:") do |receiver, _|
            action_names(receiver)
          end
          Platform::Mac::O.method(klass, "accessibilityPerformAction:", args: [:pointer], encoding: "v@:@") do |receiver, _, name|
            perform_native(receiver, Platform::Mac::O.text(name))
          end
          {
            "accessibilityPerformPress" => "AXPress",
            "accessibilityPerformIncrement" => "AXIncrement",
            "accessibilityPerformDecrement" => "AXDecrement"
          }.each do |selector, action|
            Platform::Mac::O.method(klass, selector, result: :bool, encoding: "B@:") do |receiver, _|
              perform_native(receiver, action) ? 1 : 0
            end
          end
        end
        @installed = true
      end

      def native_element(window, tree, entry, parent)
        o = Platform::Mac::O
        node = entry.node
        element = o.send(o.klass("ZaniahAccessibilityElement"), "accessibilityElementWithRole:frame:label:parent:",
          o.string(ROLES.fetch(node.role, "AXGroup")), screen_bounds(window, tree.bounds(entry)),
          o.string(node.label || node.value&.to_s || node.role.to_s), parent,
          args: [:pointer, :rect, :pointer, :pointer])
        ELEMENTS[element] = [window, node, tree.bounds(entry)]
        o.send(element, "setAccessibilityFrameInParentSpace:", parent_bounds(tree, entry), args: [:rect], result: :void)
        o.send(element, "setAccessibilityEnabled:", node.states[:disabled] ? 0 : 1, args: [:bool], result: :void)
        o.send(element, "setAccessibilityValue:", native_value(node.value), args: [:pointer], result: :void) unless node.value.nil?
        set_boolean(element, "setAccessibilitySelected:", node.states[:selected]) if node.states.key?(:selected)
        set_boolean(element, "setAccessibilityExpanded:", node.states[:expanded]) unless node.states[:expanded].nil?
        unless entry.children.empty?
          children = mutable_array
          entry.children.each { |child| append(children, native_element(window, tree, child, element)) }
          o.send(element, "setAccessibilityChildren:", children, args: [:pointer], result: :void)
        end
        element
      end

      def screen_bounds(window, bounds)
        bounds ||= Bounds.new(0, 0, window.content_size.width, window.content_size.height)
        Platform::Mac::O.send(window.handle, "convertRectToScreen:",
          [bounds.x, window.content_size.height - bounds.bottom, bounds.width, bounds.height], args: [:rect], result: :rect)
      end

      def parent_bounds(tree, entry)
        bounds = tree.bounds(entry)
        parent = entry.parent && tree.bounds(entry.parent)
        [bounds.x - (parent&.x || 0), bounds.y - (parent&.y || 0), bounds.width, bounds.height]
      end

      def action_names(receiver)
        _window, node, _bounds = ELEMENTS[receiver]
        names = mutable_array
        NATIVE_ACTIONS.each { |name, actions| append(names, Platform::Mac::O.string(name)) if node && (node.actions & actions).any? }
        names
      end

      def perform_native(receiver, name)
        window, node, bounds = ELEMENTS[receiver]
        action = NATIVE_ACTIONS[name]&.find { |candidate| node&.actions&.include?(candidate) }
        !!(action && Accessibility.perform(window, node, action, bounds: bounds))
      rescue StandardError
        false
      end

      def close(window) = ELEMENTS.delete_if { |_element, (owner, _node, _bounds)| owner.equal?(window) }

      def native_value(value)
        Platform::Mac::O.string(value.is_a?(Array) || value.is_a?(Hash) ? value.inspect : value.to_s)
      end

      def mutable_array = Platform::Mac::O.send(Platform::Mac::O.klass("NSMutableArray"), "array")
      def append(array, value) = Platform::Mac::O.send(array, "addObject:", value, args: [:pointer], result: :void)
      def set_boolean(element, selector, value) = Platform::Mac::O.send(element, selector, value ? 1 : 0, args: [:bool], result: :void)

      def notify(window, object)
        function = Platform::Mac::APPKIT.fn(:NSAccessibilityPostNotification,
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
        function.call(object, Platform::Mac::O.string("AXLayoutChanged"))
        if window.accessibility_tree.changes.any? { |change| change.after&.role == :status }
          function.call(object, Platform::Mac::O.string("AXAnnouncementRequested"))
        end
      end
    end
  end
end
