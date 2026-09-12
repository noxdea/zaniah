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

      def initialize(commands, open: false, placeholder: "Type a command…")
        @commands, @query, @placeholder = commands.to_a, "", placeholder
        super(Div.new, title: "Command palette", open: open, width: 520)
      end

      def build(cx)
        field = SearchInput.new(@query, placeholder: @placeholder).on_change do |value, context|
          @query = value
          context.window.request_frame
        end
        matches = @commands.select { |label, _| @query.empty? || label.to_s.downcase.include?(@query.downcase) }.first(20)
        results = Div.new.gap(1).children(matches.map do |label, callback|
          Button.new(label.to_s, variant: :ghost).w_full.on_click do |event, context|
            callback&.call(event, context)
            dismiss(event, context)
          end
        end)
        @content = Div.new.gap(cx.theme.spacing[2]).child(field).child(results)
        super
      end

      def tui_cells(*) = "> #{@query}\n" + @commands.map(&:first).join("\n")
      def accessibility_node(cx) = @open && node(:dialog, label: "Command palette", states: {modal: true}, children: [Accessibility.node(role: :textbox, label: @placeholder, value: @query), Accessibility.node(role: :list, children: @commands.map { |label, _| Accessibility.node(role: :listitem, label: label) })], actions: [:dismiss])
    end
  end
end
