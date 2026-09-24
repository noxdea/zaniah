# frozen_string_literal: true

module Zaniah
  module UI
    class Modal < OverlayComponent
      def initialize(content, title: nil, open: true, close_on_scrim: true, width: 440)
        super(open: open, modal: true)
        @content, @title, @close_on_scrim, @panel_width = content, title&.to_s, !!close_on_scrim, width
        @focus_scope.on_action = ->(action) { action == :dismiss && dismiss(nil, @cx) }
      end

      def build(cx)
        return Div.new.style(display: :none) unless @visible
        @cx = cx
        panel = Div.new.w(@panel_width).max_h(percent(90)).p(cx.theme.spacing[4]).gap(cx.theme.spacing[3])
          .bg(cx.theme.colors.surface).border(1).border_color(cx.theme.colors.border)
          .rounded(cx.theme.radii[:lg]).style(shadows: cx.theme.shadows[:lg], z_index: Scene::LAYER_MODAL)
          .on_mouse_down { true }
        if @title
          panel.child(Div.new.flex_row.items_center.gap(cx.theme.spacing[2])
            .child(Label.new(@title, size: :lg).flex_1)
            .child(IconButton.new(:close, label: "Close", variant: :ghost).on_click { |event, context| dismiss(event, context) }))
        end
        panel.child(@content)
        Overlay.new.items_center.justify_center.bg(cx.theme.colors.overlay_scrim)
          .style(z_index: Scene::LAYER_MODAL - 1)
          .on_mouse_down { |event, context| @close_on_scrim && dismiss(event, context) }.child(panel)
      end

      def tui_cells(*) = "┌ #{@title || "Dialog"} ┐\n#{@content.respond_to?(:tui_cells) ? @content.tui_cells : ""}\n└#{"─" * 8}┘"
      def accessibility_node(cx) = @open && node(:dialog, label: @title, states: {modal: true}, children: [@content.respond_to?(:accessibility_node) ? @content.accessibility_node(cx) : nil].compact, actions: [:dismiss])
    end

    class Dialog < Modal; end

    class Drawer < Modal
      def initialize(content, side: :right, width: 360, **options)
        raise ArgumentError, "drawer side must be left or right" unless %i[left right].include?(side)
        @side = side
        super(content, width: width, **options)
      end

      def build(cx)
        return Div.new.style(display: :none) unless @visible
        @cx = cx
        panel = Div.new.w(@panel_width).h_full.p(cx.theme.spacing[4]).gap(cx.theme.spacing[3])
          .bg(cx.theme.colors.surface).style(position: :absolute, top: 0, @side => 0, z_index: Scene::LAYER_MODAL)
          .on_mouse_down { true }
        panel.child(Label.new(@title, size: :lg)) if @title
        panel.child(@content)
        Overlay.new.bg(cx.theme.colors.overlay_scrim).style(z_index: Scene::LAYER_MODAL - 1)
          .on_mouse_down { |event, context| @close_on_scrim && dismiss(event, context) }.child(panel)
      end
    end

    class Toast < Component
      class Queue
        def initialize = @items = []
        def push(message, **options) = (@items << [message.to_s, options]; self)
        def shift = @items.shift
        def first = @items.first
        def empty? = @items.empty?
        def size = @items.size
      end

      variants variant: {
        info: ->(theme) { {color: theme.colors.info} },
        success: ->(theme) { {color: theme.colors.success} },
        warning: ->(theme) { {color: theme.colors.warning} },
        danger: ->(theme) { {color: theme.colors.danger} }
      }

      def initialize(message = nil, variant: :info, queue: nil)
        super()
        @message, @variant, @queue = message&.to_s, variant, queue
      end

      def dismiss
        @queue&.shift
        @message = nil unless @queue
        @cx&.window&.request_frame
        self
      end

      def build(cx)
        @cx = cx
        message, options = @queue&.first || [@message, {variant: @variant}]
        return Div.new.style(display: :none) unless message
        color = self.class.variant_style(cx.theme, variant: options.fetch(:variant, @variant))[:color]
        Anchored.new(anchor: Point.new(cx.window.content_size.width - 332, 16)).w(316).p(cx.theme.spacing[3])
          .flex_row.items_center.gap(cx.theme.spacing[2]).bg(cx.theme.colors.surface).border(1)
          .border_color(color).rounded(cx.theme.radii[:md]).style(shadows: cx.theme.shadows[:md], z_index: Scene::LAYER_POPUP)
          .child(Label.new(message).flex_1)
          .child(IconButton.new(:close, label: "Dismiss", size: :sm, variant: :ghost).on_click { dismiss })
      end

      def tui_cells(*) = @queue&.first&.first || @message || ""
      def accessibility_node(_cx) = (message = @queue&.first&.first || @message) && node(:status, label: message, states: {live: true}, actions: [:dismiss])
    end

    class CommandPalette < Modal
      attr_reader :query

      def self.from(registry, **options)
        commands = registry.entries.map do |name, title|
          command = registry.command(name)
          action = command&.name || name
          enabled = lambda do |cx|
            if cx&.dispatcher&.respond_to?(:available?)
              cx.dispatcher.available?(action) == :enabled
            elsif command&.enabled
              command.enabled.arity.zero? ? command.enabled.call : command.enabled.call(cx)
            else
              true
            end
          end
          callback = lambda do |_event, cx|
            if cx.dispatcher.respond_to?(:perform)
              cx.dispatcher.perform(action, source: :palette)
            else
              registry.call(name, cx)
            end
          end
          [title, callback, enabled]
        end
        new(commands, **options)
      end

      def initialize(commands, open: false, placeholder: "Type a command…", matcher: nil)
        @commands = commands.to_a.map { |label, callback, enabled| [label.to_s, callback, enabled] }
        @matcher = Matcher::Session.new(@commands.map(&:first), matcher || Zaniah.configuration.matcher || Matcher::Substring.new)
        @query, @placeholder, @selected_index = "", placeholder, 0
        @focus_search = !!open
        super(Div.new, title: "Command palette", open: open, width: 520)
        @focus_scope.context[:in_palette] = true
        @focus_scope.on_action = ->(action) { palette_action(action) }
      end

      def build(cx)
        field = @search = SearchInput.new(@query, placeholder: @placeholder).on_change do |value, context|
          @query = value
          @selected_index = 0
          context.window.request_frame
        end
        matches = filtered
        unless matches[@selected_index] && enabled?(matches[@selected_index][0], cx)
          @selected_index = matches.index { |entry, _| enabled?(entry, cx) } || 0
        end
        results = Div.new.gap(1).children(matches.map.with_index do |(entry, match), index|
          label = entry[0]
          button = match.ranges.empty? ? Button.new(label, variant: index == @selected_index ? :secondary : :ghost) :
            HighlightedButton.new(label, ranges: match.ranges, variant: index == @selected_index ? :secondary : :ghost)
          button.disabled(!enabled?(entry, cx)).w_full.on_click do |event, context|
            choose(index, event, context)
          end
        end)
        @content = Div.new.gap(cx.theme.spacing[2]).child(field).child(results)
        super
      end

      def open(value = true)
        @focus_search = true if value && !open?
        super
      end

      def prepaint(bounds, state, cx)
        super
        return unless @focus_search && @open && @search&.focus_handle
        cx.dispatcher.focus(@search.focus_handle, origin: :keyboard)
        @focus_search = false
      end

      def tui_cells(*) = "> #{@query}\n" + filtered.map { |entry, _| entry[0] }.join("\n")

      def accessibility_node(cx)
        return unless @open
        matches = filtered
        active = matches[@selected_index]&.last&.index
        items = matches.map.with_index do |(entry, match), index|
          enabled = enabled?(entry, cx || @cx)
          Accessibility.node(role: :listitem, id: "palette-option-#{match.index}", label: entry[0],
            states: {selected: index == @selected_index, disabled: !enabled}, actions: enabled ? [:press] : [])
        end
        node(:dialog, label: "Command palette", states: {modal: true}, children: [
          Accessibility.node(role: :searchbox, label: @placeholder, value: @query),
          Accessibility.node(role: :list, states: {active_descendant: active && "palette-option-#{active}"}, children: items)
        ], actions: [:dismiss])
      end

      def accessibility_action(item, action)
        return dismiss(nil, @cx) if action == :dismiss
        return false unless action == :press
        index = filtered.index { |_entry, match| "palette-option-#{match.index}" == item.id }
        index && choose(index, nil, @cx)
      end

      private

      def filtered
        @matcher.results(@query).first(20).filter_map do |match|
          entry = @commands[match.index]
          [entry, match] if entry
        end
      end

      def enabled?(entry, cx)
        callback, predicate = entry[1], entry[2]
        callback && (!predicate || (predicate.arity.zero? ? predicate.call : predicate.call(cx)))
      end

      def palette_action(action)
        case action
        when :previous_option then move(-1)
        when :next_option then move(1)
        when :choose_option, :activate then choose(@selected_index, nil, @cx)
        when :dismiss then dismiss(nil, @cx)
        else false
        end
      end

      def move(step)
        matches = filtered
        return false if matches.empty?
        matches.length.times do
          @selected_index = (@selected_index + step) % matches.length
          break if enabled?(matches[@selected_index][0], @cx)
        end
        @cx&.window&.request_frame
        true
      end

      def choose(index, event, cx)
        entry = filtered[index]&.first
        return false unless entry && enabled?(entry, cx)
        entry[1].call(event, cx)
        dismiss(event, cx)
      end
    end
  end
end
