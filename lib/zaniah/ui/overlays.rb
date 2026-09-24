# frozen_string_literal: true

module Zaniah
  module UI
    module Placement
      module_function

      def place(anchor, size, viewport, side: :bottom, offset: 8)
        raise ArgumentError, "side must be top, bottom, left, or right" unless %i[top bottom left right].include?(side)
        anchor = Bounds.new(anchor.x, anchor.y, 0, 0) if anchor.is_a?(Point)
        raise ArgumentError, "anchor must be a Point or Bounds" unless anchor.is_a?(Bounds)
        width, height = size.is_a?(Size) ? [size.width, size.height] : size
        candidates = [side, {top: :bottom, bottom: :top, left: :right, right: :left}.fetch(side)]
        chosen = candidates.find { |candidate| fits?(anchor, width, height, viewport, candidate, offset) } || side
        x, y = coordinates(anchor, width, height, chosen, offset)
        Bounds.new(x.clamp(viewport.x, [viewport.right - width, viewport.x].max),
          y.clamp(viewport.y, [viewport.bottom - height, viewport.y].max), width, height)
      end

      def fits?(anchor, width, height, viewport, side, offset)
        x, y = coordinates(anchor, width, height, side, offset)
        %i[top bottom].include?(side) ? y >= viewport.y && y + height <= viewport.bottom : x >= viewport.x && x + width <= viewport.right
      end
      private_class_method :fits?

      def coordinates(anchor, width, height, side, offset)
        case side
        when :top then [anchor.x + (anchor.width - width) / 2.0, anchor.y - height - offset]
        when :bottom then [anchor.x + (anchor.width - width) / 2.0, anchor.bottom + offset]
        when :left then [anchor.x - width - offset, anchor.y + (anchor.height - height) / 2.0]
        when :right then [anchor.right + offset, anchor.y + (anchor.height - height) / 2.0]
        end
      end
      private_class_method :coordinates
    end

    class OverlayComponent < Component
      def initialize(open: true, modal: false)
        super()
        @open, @visible, @modal = !!open, !!open, !!modal
        @entered = !@open
        @focus_scope = Input::FocusHandle.new(owner: self, focusable: false)
      end

      def focus_handle = @focus_scope
      def open? = @open
      def visible? = @visible
      def open(value = true)
        value = !!value
        return self if value == @open
        @open = value
        if value
          @visible, @entered = true, false
          @cx&.window&.request_frame
        else
          @cx ? animate_close(@cx) : @visible = false
        end
        self
      end
      def close = open(false)
      def on_close(&block) = (@on_close = block; self)

      def request_layout(cx)
        @cx = cx
        animate_open(cx) if @open && @visible && !@entered
        @focus_scope.children.dup.each { |child| child.parent = nil }
        super
      end

      def prepaint(bounds, state, cx)
        super
        tree = cx.dispatcher.focus_tree
        if @open && @modal
          unless @trapped
            @return_focus, @dispatcher = cx.dispatcher.focused, cx.dispatcher
            tree.trap(@focus_scope)
            @trapped = true
          end
          focused_inside = cx.dispatcher.focused&.ancestors&.include?(@focus_scope)
          target = tree.next
          cx.dispatcher.focus(target, origin: :keyboard) if target && !focused_inside
        elsif @trapped
          tree.release_trap(@focus_scope)
          @dispatcher.focus(@return_focus) if @return_focus&.focusable
          @trapped = false
        end
      end

      def paint(bounds, state, prepaint, cx)
        @root.paint_style(opacity: cx.animator.value(visibility_key, @open ? 1.0 : 0.0)) if @visible
        super
      end

      protected

      def dismiss(event = nil, cx = nil)
        return false unless @open
        @open = false
        @on_close&.call(event, cx)
        cx&.dispatcher&.focus_tree&.release_trap(@focus_scope)
        cx&.dispatcher&.focus(@return_focus) if @return_focus&.focusable
        @trapped = false
        animate_close(cx) if cx
        @visible = false unless cx
        cx&.window&.request_frame
        true
      end

      def viewport(cx) = Bounds.new(0, 0, cx.window.content_size.width, cx.window.content_size.height)

      def visibility_key = [:overlay, object_id]

      def animate_open(cx)
        @entered = true
        cx.animator.animate(visibility_key, from: 0.0, to: 1.0,
          duration: cx.theme.motion.duration_base, easing: :ease_out)
      end

      def animate_close(cx)
        cx.animator.animate(visibility_key, from: cx.animator.value(visibility_key, 1.0), to: 0.0,
          duration: cx.theme.motion.duration_base, easing: :ease_in) do
          @visible = false
          cx.window.request_frame
        end
      end
    end

    class Popover < OverlayComponent
      def initialize(content, anchor:, side: :bottom, width: 240, height: 120, open: true, modal: false)
        super(open: open, modal: modal)
        @content, @anchor, @side, @panel_size = content, anchor, side, Size.new(width, height)
      end

      def build(cx)
        return Div.new.style(display: :none) unless @visible
        box = Placement.place(@anchor, @panel_size, viewport(cx), side: @side)
        panel = Anchored.new(anchor: Point.new(box.x, box.y)).w(box.width).h(box.height)
          .p(cx.theme.spacing[3]).bg(cx.theme.colors.surface).border(1)
          .border_color(cx.theme.colors.border).rounded(cx.theme.radii[:md])
          .style(shadows: cx.theme.shadows[:md], z_index: Scene::LAYER_POPUP)
          .on_mouse_down { true }.child(@content)
        Overlay.new.style(z_index: Scene::LAYER_POPUP - 1).on_mouse_down { |event, context| dismiss(event, context) }.child(panel)
      end

      def tui_cells(*) = "┌ #{@content.respond_to?(:tui_cells) ? @content.tui_cells : "popover"} ┐"
      def accessibility_node(cx) = @open && node(:group, children: [@content.accessibility_node(cx)].compact)
    end

    class Tooltip < Popover
      def initialize(text, **options)
        @text = text.to_s
        super(nil, height: 32, width: [@text.length * 8 + 20, 80].max, modal: false, **options)
      end

      def build(cx)
        @content = Label.new(@text, size: :sm)
        super
      end

      def tui_cells(*) = @text
      def accessibility_node(_cx) = @open && node(:tooltip, label: @text)
    end

    class Menu < OverlayComponent
      attr_reader :selected_index

      def initialize(items, anchor: Point.new(0, 0), open: true, modal: true, dispatcher: nil, registry: nil, target_focus: nil)
        super(open: open, modal: modal)
        @dispatcher, @registry, @target_focus = dispatcher, registry, target_focus
        @model = items.is_a?(Zaniah::Menu) || (items.is_a?(Array) && items.any? && items.all? { |item| item.is_a?(Zaniah::Menu::Item) })
        items = items.resolve(registry: registry, keymap: dispatcher&.keymap) if items.is_a?(Zaniah::Menu)
        @stack = []
        @items, @anchor = normalize_items(items), anchor
        @selected_index = @items.index { |item| item[:enabled] } || 0
      end

      def prepaint(bounds, state, cx)
        super
        current_target = target_focus
        @return_focus = current_target if @trapped && current_target&.focusable
      end

      def build(cx)
        return Div.new.style(display: :none) unless @visible
        @cx = cx
        width = [@items.map { |item| item[:label].length * 8 + (item[:shortcut] ? 100 : 24) }.max || 80, cx.window.content_size.width].min
        height = [@items.length * 26 + 8, cx.window.content_size.height].min
        box = @panel_box = Bounds.new(@anchor.x.clamp(0, cx.window.content_size.width - width),
          @anchor.y.clamp(0, cx.window.content_size.height - height), width, height)
        panel = Anchored.new(anchor: Point.new(box.x, box.y)).w(box.width).p(4).gap(1)
          .bg(cx.theme.colors.surface).border(1).border_color(cx.theme.colors.border)
          .rounded(cx.theme.radii[:sm]).style(z_index: Scene::LAYER_POPUP)
          .focusable(context: {in_menu: true}) { |action| menu_action(action) }
          .on_mouse_down { true }
        @items.each_with_index do |item, index|
          color = item[:enabled] ? cx.theme.colors.text : cx.theme.colors.text_muted
          row = Div.new.h(26).p([4, 8]).rounded(3).cursor(:pointer)
            .bg(index == @selected_index ? cx.theme.colors.surface_hover : "#0000")
            .on_hover { @selected_index = index if item[:enabled] }
            .on_click { |event, context| choose(index, event, context) }
            .disabled(!item[:enabled])
          if @model
            row.flex_row.items_center.gap(6)
              .child(Text.new("#{item[:checked] ? '✓ ' : ''}#{item[:label]}#{item[:role] == :submenu ? ' ▶' : ''}", size: 13, color: color).flex_1)
            row.child(Kbd.new(item[:shortcut])) if item[:shortcut]
          else
            row.child(Text.new(item[:label], size: 13, color: color))
          end
          panel.child(row)
        end
        Overlay.new.style(z_index: Scene::LAYER_POPUP - 1).on_mouse_down { |event, context| dismiss(event, context) }.child(panel)
      end

      def tui_cells(*) = @items.map.with_index { |item, index| "#{index == @selected_index ? ">" : " "} #{item[:checked] ? '✓ ' : ''}#{item[:label]}#{item[:shortcut] ? "  #{Kbd.new(item[:shortcut], platform: :tui).tui_cells}" : ''}" }.join("\n")
      def popup_data = {labels: @items.map { |item| item[:label] }.freeze, enabled: @items.map { |item| item[:enabled] }.freeze, selected_index: @selected_index, bounds: @panel_box}
      def accessibility_node(_cx)
        return unless @open
        node(:menu, children: @items.map do |item|
          states = {disabled: !item[:enabled]}
          states[:checked] = !!item[:checked] if @model
          Accessibility.node(role: item[:role] == :separator ? :separator : :menuitem,
            label: item[:label], states: states, actions: item[:enabled] ? [:press] : [])
        end)
      end

      private

      def normalize_items(items)
        raise ArgumentError, "menu items must be label/callback pairs" unless items.is_a?(Array)
        items.map do |item|
          if item.is_a?(Zaniah::Menu::Item)
            if item.separator?
              next {label: "────────", callback: nil, enabled: false, role: :separator}
            end
            if item.submenu?
              next {label: item.title.to_s, callback: nil, enabled: true, role: :submenu, item: item}
            end
            state = @dispatcher&.available?(item.action)
            next {label: item.title.to_s, callback: ->(*) { @dispatcher.perform(item.action, source: :menu) },
              enabled: state == :enabled, checked: @dispatcher&.checked?(item.action), shortcut: item.shortcut, role: item.role}
          end
          label, callback = item.is_a?(Hash) ? [item.fetch(:label), item[:on_select]] : item
          raise ArgumentError, "menu item label must be a string" unless label.is_a?(String)
          raise ArgumentError, "menu item callback must be callable or nil" unless callback.nil? || callback.respond_to?(:call)
          {label: label, callback: callback, enabled: !callback.nil?}
        end
      end

      def menu_action(action)
        case action
        when :previous_option then move(-1)
        when :next_option then move(1)
        when :first then @selected_index = @items.index { |item| item[:enabled] } || 0
        when :last then @selected_index = @items.rindex { |item| item[:enabled] } || 0
        when :activate then choose(@selected_index, nil, @cx)
        when :dismiss then dismiss(nil, @cx)
        else return false
        end
        @cx.window.request_frame
        true
      end

      def move(step)
        @items.length.times do
          @selected_index = (@selected_index + step) % @items.length
          break if @items[@selected_index][:enabled]
        end
      end

      def choose(index, event, cx)
        item = @items[index]
        return false unless item && item[:enabled]
        if item[:role] == :back
          @items = @stack.pop
          @selected_index = @items.index { |entry| entry[:enabled] } || 0
          cx&.window&.request_frame
          return true
        end
        if item[:role] == :submenu
          @stack << @items
          children = Zaniah::Menu.new([item[:item]]).children_for(item[:item], registry: @registry, keymap: @dispatcher&.keymap)
          @items = [{label: "← Back", callback: nil, enabled: true, role: :back}] + with_target_focus { normalize_items(children) }
          @selected_index = 0
          cx&.window&.request_frame
          return true
        end
        callback = item[:callback]
        return false unless callback
        result = with_target_focus { callback.arity.zero? ? callback.call : callback.call(event, cx) }
        return false if @model && result == false
        dismiss(event, cx)
      end

      def with_target_focus
        current_target = target_focus
        return yield unless current_target&.focusable
        current = @dispatcher.focused
        @dispatcher.focus(current_target)
        yield
      ensure
        @dispatcher.focus(current) if current&.focusable && !current.equal?(current_target)
      end

      def target_focus = @target_focus.respond_to?(:call) ? @target_focus.call : @target_focus
    end

    class ContextMenu < Menu; end

    class MenuBar < Component
      def self.from(menu) = new(menu)

      def initialize(menus)
        super()
        @model = menus if menus.is_a?(Zaniah::Menu)
        @menus = @model ? [] : menus.to_a
      end

      def build(cx)
        return build_model(cx) if @model

        Div.new.flex_row.items_center.gap(2).children(@menus.map do |label, items|
          Button.new(label.to_s, size: :sm, variant: :ghost).on_click { |_event, context| context.window.context_menu(items, position: @bounds ? Point.new(@bounds.x, @bounds.bottom) : Point.new(0, 0)) }
        end)
      end

      def tui_cells(_bounds = nil, cx = nil)
        labels = @model ? resolved_sections(cx || @cx).map(&:title) : @menus.map(&:first)
        labels.compact.join(" | ")
      end
      def accessibility_node(cx)
        labels = @model ? resolved_sections(cx || @cx).map(&:title) : @menus.map(&:first)
        children = labels.compact.map { |label| Accessibility.node(role: :menuitem, label: label) }
        children << @active_menu.accessibility_node(cx) if @active_menu&.open?
        node(:menubar, children: children)
      end

      private

      def resolved_sections(cx)
        @model.resolve(registry: cx&.window&.app&.actions, keymap: cx&.dispatcher&.keymap)
      end

      def focus_target(handle)
        return unless handle
        owner = handle.owner
        while owner
          if owner.is_a?(Component) && owner.focus_handle.equal?(handle)
            target = owner
            return -> { target.focus_handle }
          end
          owner = owner.respond_to?(:parent) ? owner.parent : nil
        end
        -> { handle }
      end

      def build_model(cx)
        @cx = cx
        sections = resolved_sections(cx)
        bar = Div.new.flex_row.items_center.gap(2).h(28)
        sections.each_with_index do |section, index|
          next unless section.title
          button = Button.new(section.title, size: :sm, variant: :ghost)
          if section.submenu?
            button.on_click do |_event, context|
              target_focus = focus_target(context.dispatcher.previous_focused)
              current_target = target_focus&.call
              context.dispatcher.focus(current_target) if current_target&.focusable
              children = @model.children_for(section, registry: context.window.app&.actions, keymap: context.dispatcher.keymap)
              @active_menu = Menu.new(children, dispatcher: context.dispatcher, registry: context.window.app&.actions,
                target_focus: target_focus,
                anchor: @bounds ? Point.new(@bounds.x + index * 70, @bounds.bottom) : Point.new(0, 0))
              context.window.request_frame
            end
          else
            button.disabled(cx.dispatcher.available?(section.action) != :enabled)
              .on_click do |_event, context|
                current_target = focus_target(context.dispatcher.previous_focused)&.call
                context.dispatcher.focus(current_target) if current_target&.focusable
                context.dispatcher.perform(section.action, source: :menu)
              end
          end
          bar.child(button)
        end
        bar.child(@active_menu) if @active_menu&.open?
        bar
      end
    end

    class Dropdown < Component
      attr_reader :value

      def initialize(label, items:, value: nil)
        super()
        @label, @items, @value = label.to_s, items.to_a, value
      end

      def on_change(&block) = (@on_change = block; self)

      def build(_cx)
        Button.new(@value ? @value.to_s : @label, variant: :secondary).icon(:menu, position: :trailing).on_click do |_event, context|
          pairs = @items.map do |label, value = label|
            [label.to_s, ->(event = nil, cx = context) { @value = value; @on_change&.call(value, event, cx); cx.window.request_frame }]
          end
          context.window.context_menu(pairs, position: @bounds ? Point.new(@bounds.x, @bounds.bottom) : Point.new(0, 0))
        end
      end

      def tui_cells(*) = "#{@label}: #{@value || "▾"}"
      def accessibility_node(_cx) = node(:button, label: @label, value: @value, states: {expanded: false}, actions: [:press])
    end
  end
end
