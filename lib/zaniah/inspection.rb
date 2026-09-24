# frozen_string_literal: true

module Zaniah
  module Inspection
    SOURCE_NODES = ObjectSpace::WeakMap.new

    Entry = Data.define(:element, :type, :key, :test_id, :bounds, :style, :tooltip,
      :context_menu, :handlers, :focusable, :focused, :children) do
      def name = type
      def object = element
      def focusable? = focusable
      def focused? = focused
    end

    Overlays = Data.define(:tooltip, :popup, :menu)
    FrameInfo = Data.define(:number, :stats)

    AccessibilitySnapshot = Data.define(:root) do
      def query(role: nil, label: nil, states: {})
        raise ArgumentError, "label must be a String or Regexp" unless label.nil? || label.is_a?(String) || label.is_a?(Regexp)
        return [].freeze unless root

        found = []
        pending = [[root, []]]
        until pending.empty?
          node, path = pending.pop
          if (!role || node.role == role) &&
              (!label || (node.label && (label.is_a?(Regexp) ? label.match?(node.label) : node.label == label))) &&
              states.all? { |key, value| node.states.key?(key) && node.states[key] == value }
            found << [node, path.freeze].freeze
          end
          node.children.each_with_index.reverse_each { |child, index| pending << [child, path + [index]] }
        end
        found.freeze
      end
    end

    Snapshot = Data.define(:root, :overlays, :text_runs, :frame, :accessibility, :hits) do
      def find(test_id: nil, type: nil) = where(test_id: test_id, type: type).first

      def where(test_id: nil, type: nil)
        return [].freeze unless root
        found = []
        pending = [root]
        until pending.empty?
          entry = pending.pop
          if (!test_id || entry.test_id == test_id) &&
              (!type || (type.is_a?(Class) ? entry.element.is_a?(type) : entry.type == type))
            found << entry
          end
          pending.concat(entry.children.reverse)
        end
        found.freeze
      end

      def at(point)
        return unless point
        owner = hits.reverse_each.find { |hit| hit.contains?(point) }&.owner
        while owner
          pending = [root].compact
          until pending.empty?
            entry = pending.pop
            return entry if entry.element.equal?(owner)
            pending.concat(entry.children)
          end
          owner = owner.respond_to?(:parent) ? owner.parent : nil
        end
        nil
      end
    end

    module_function

    def snapshot(window)
      raise ArgumentError, "expected a rendered window" unless window.respond_to?(:last_root) && window.respond_to?(:dispatcher)

      seen = {}
      root = entry(window.last_root, window, seen)
      popup = window.popup if window.respond_to?(:popup)
      popup = Platform::Headless::Popup.new(labels: copy(popup.labels), enabled: copy(popup.enabled),
        selected_index: popup.selected_index, bounds: popup.bounds) if popup
      overlays = Overlays.new(tooltip: copy(window.tooltip_state), popup: popup,
        menu: window.app&.respond_to?(:menu_bar) ? window.app.menu_bar : nil)
      text_runs = copy(window.text_runs)
      frame = FrameInfo.new(number: window.frame_number, stats: copy(window.frame_stats))
      Snapshot.new(root: root, overlays: overlays, text_runs: text_runs, frame: frame,
        accessibility: AccessibilitySnapshot.new(root: copy_accessibility(window.accessibility_tree.root)),
        hits: window.dispatcher.hit_regions)
    end

    def idle?(app)
      app.executor.idle? && app.windows.all? { |window| window.closed? || (!window.dirty? && !window.animation_active?) }
    end

    def perform(window, node, action) = Accessibility.perform(window, SOURCE_NODES[node] || node, action)

    def copy_accessibility(node)
      return unless node
      result = Accessibility::Node.new(role: node.role, label: copy(node.label), value: copy(node.value),
        bounds: node.bounds, states: copy(node.states),
        children: node.children.map { |child| copy_accessibility(child) }.freeze, actions: copy(node.actions))
      SOURCE_NODES[result] = node
      result
    end
    private_class_method :copy_accessibility

    def entry(object, window, seen)
      return unless object && !seen[object.object_id]
      seen[object.object_id] = true
      style = object.resolved_style if object.respond_to?(:resolved_style)
      style ||= object.root&.resolved_style if object.respond_to?(:root)
      handle = object.focus_handle if object.respond_to?(:focus_handle)
      items = object.context_menu_items if object.respond_to?(:context_menu_items)
      menu = items&.map { |label, callback| [label.dup.freeze, !callback.nil?].freeze }&.freeze if items.is_a?(Array)
      if items.is_a?(Menu)
        menu = items.resolve(registry: window.app&.actions, keymap: window.dispatcher.keymap).map do |item|
          [item.title.to_s.freeze, item.submenu? || (!!item.action && window.dispatcher.available?(item.action) == :enabled)].freeze
        end.freeze
      end
      Entry.new(element: object, type: object.class.name.to_s.delete_prefix("Zaniah::").freeze,
        key: object.respond_to?(:identity_key) ? copy(object.identity_key) : nil,
        test_id: object.respond_to?(:test_id) ? copy(object.test_id) : nil,
        bounds: object.respond_to?(:layout_node) ? object.layout_node&.bounds : nil,
        style: snapshot_style(style),
        tooltip: object.respond_to?(:tooltip_text) ? copy(object.tooltip_text) : nil,
        context_menu: menu, handlers: object.respond_to?(:handlers) ? copy(object.handlers) : [].freeze,
        focusable: !!handle&.focusable, focused: !!(handle && window.dispatcher.focused.equal?(handle)),
        children: object.respond_to?(:children) ? object.children.filter_map { |child| entry(child, window, seen) }.freeze : [].freeze)
    end
    private_class_method :entry

    def snapshot_style(style)
      values = style ? style.to_h : {}.freeze
      return values if values.frozen? && values.values.none? { |value| value.is_a?(String) || value.is_a?(Array) || value.is_a?(Hash) }
      copy(values)
    end
    private_class_method :snapshot_style

    def copy(value)
      case value
      when String then value.dup.freeze
      when Array then value.map { |item| copy(item) }.freeze
      when Hash then value.to_h { |key, item| [copy(key), copy(item)] }.freeze
      else value
      end
    end
    private_class_method :copy
  end

  def self.bundled_font_path = File.expand_path("../../assets/fonts/Abel-Regular.ttf", __dir__)
end
