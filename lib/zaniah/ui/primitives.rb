# frozen_string_literal: true

module Zaniah
  module UI
    class Label < Component
      variants tone: {
        default: ->(theme) { {color: theme.colors.text} },
        muted: ->(theme) { {color: theme.colors.text_muted} },
        inverse: ->(theme) { {color: theme.colors.text_inverse} }
      }, size: {
        xs: ->(theme) { {size: theme.typography.size_xs} },
        sm: ->(theme) { {size: theme.typography.size_sm} },
        md: ->(theme) { {size: theme.typography.size_md} },
        lg: ->(theme) { {size: theme.typography.size_lg} },
        xl: ->(theme) { {size: theme.typography.size_xl} }
      }

      attr_reader :text

      def initialize(text, tone: :default, size: :md, wrap: :none)
        super()
        @text, @tone, @size, @wrap = text.to_s.encode(Encoding::UTF_8), tone, size, wrap
      end

      def build(cx)
        options = self.class.variant_style(cx.theme, tone: @tone, size: @size)
        Text.new(@text, size: options[:size], color: options[:color], wrap: @wrap)
      end

      def tui_cells(*) = @text
      def accessibility_node(_cx) = node(:text, label: @text)
    end

    class Icon < Component
      GLYPHS = {check: "✓", close: "×", search: "⌕", menu: "☰", info: "ⓘ", warning: "⚠"}.freeze

      def initialize(source, size: 16, color: nil, label: nil)
        super()
        @source, @size, @color, @label = source, Float(size), color, label
      end

      def build(cx)
        color = svg_color(@color || cx.theme.colors.text)
        icon = case @source
        when Symbol then SVG.open(File.expand_path("../../../assets/icons/#{@source}.svg", __dir__), color: color)
        when String
          @source.lstrip.start_with?("<svg") ? SVG.parse(@source, color: color) : SVG.open(@source, color: color)
        else @source
        end
        raise ArgumentError, "icon source must be SVG markup, a path, a bundled name, or an element" unless icon.respond_to?(:style)
        icon.style(width: @size, height: @size)
      end

      def tui_cells(*) = GLYPHS[@source]
      def accessibility_node(_cx) = @label && node(:image, label: @label)

      private

      def svg_color(value)
        color = Color.parse(value)
        "rgba(#{color.to_a.first(3).map { |channel| (channel * 255).round }.join(",")},#{color.a})"
      end
    end

    class Divider < Component
      def initialize(axis: :horizontal)
        super()
        raise ArgumentError, "axis must be horizontal or vertical" unless %i[horizontal vertical].include?(axis)
        @axis = axis
      end

      def build(cx)
        Div.new.style(**(@axis == :horizontal ? {height: 1, width: percent(100)} : {width: 1, height: percent(100)}), background: cx.theme.colors.border)
      end

      def tui_cells(*) = @axis == :horizontal ? "─" : "│"
      def accessibility_node(_cx) = node(:separator)
    end

    class Spacer < Component
      def initialize(size = nil)
        super()
        @size = size
      end

      def build(_cx)
        @size ? Div.new.style(width: @size, height: @size) : Div.new.flex_1
      end

      def tui_cells(*) = ""
    end

    class Card < Component
      attr_reader :children

      def initialize(*children)
        super()
        @children = children.compact
      end

      def child(value) = (@children << value if value; self)

      def build(cx)
        Div.new.p(cx.theme.spacing[4]).gap(cx.theme.spacing[2]).bg(cx.theme.colors.surface)
          .border(1).border_color(cx.theme.colors.border).rounded(cx.theme.radii[:md])
          .style(shadows: cx.theme.shadows[:sm]).children(@children)
      end

      def tui_cells(*) = "┌ card ┐"
      def accessibility_node(cx) = node(:group, children: @children.filter_map { |child| child.accessibility_node(cx) if child.respond_to?(:accessibility_node) })
    end

    class Badge < Component
      variants variant: {
        neutral: ->(theme) { {background: theme.colors.surface_hover, color: theme.colors.text} },
        accent: ->(theme) { {background: theme.colors.accent, color: theme.colors.accent_text} },
        success: ->(theme) { {background: theme.colors.success, color: theme.colors.text_inverse} },
        warning: ->(theme) { {background: theme.colors.warning, color: theme.colors.text_inverse} },
        danger: ->(theme) { {background: theme.colors.danger, color: theme.colors.text_inverse} }
      }

      def initialize(text, variant: :neutral)
        super()
        @text, @variant = text.to_s, variant
      end

      def build(cx)
        style = self.class.variant_style(cx.theme, variant: @variant)
        Div.new.flex_row.items_center.p([2, 7]).bg(style[:background]).rounded(cx.theme.radii[:full])
          .child(Text.new(@text, size: cx.theme.typography.size_xs, color: style[:color]))
      end

      def tui_cells(*) = "[#{@text}]"
      def accessibility_node(_cx) = node(:text, label: @text)
    end

    class Avatar < Component
      def initialize(name, image: nil, size: 32)
        super()
        @name, @image, @size = name.to_s, image, Float(size)
      end

      def build(cx)
        content = @image ? Image.new(@image).w_full.h_full : Text.new(initials, size: @size * 0.38, color: cx.theme.colors.accent_text)
        Div.new.w(@size).h(@size).items_center.justify_center.overflow_hidden
          .bg(cx.theme.colors.accent).rounded(cx.theme.radii[:full]).child(content)
      end

      def tui_cells(*) = "(#{initials})"
      def accessibility_node(_cx) = node(:image, label: @name)

      private

      def initials = @name.split.take(2).map { |part| part[0] }.join.upcase
    end

    class Skeleton < Component
      def initialize(width: 120, height: 16)
        super()
        @width, @height = width, height
      end

      def build(cx)
        opacity = 1.0
        unless cx.theme.motion.reduced?
          animation_key = [:skeleton, object_id]
          unless cx.animator.animating?(animation_key)
            from = cx.animator.value(animation_key, 0.45)
            cx.animator.animate(animation_key, from: from, to: from > 0.7 ? 0.45 : 1.0,
              duration: cx.theme.motion.duration_slow, easing: :ease_in_out)
          end
          opacity = cx.animator.value(animation_key, 0.45)
        end
        Div.new.w(@width).h(@height).bg(cx.theme.colors.surface_hover).rounded(cx.theme.radii[:sm]).paint_style(opacity: opacity)
      end
      def tui_cells(*) = "░░░"
      def accessibility_node(_cx) = node(:progressbar, label: "Loading", states: {busy: true})
    end

    class EmptyState < Component
      def initialize(title, message: nil, icon: nil, action: nil)
        super()
        @title, @message, @icon, @action = title.to_s, message&.to_s, icon, action
      end

      def build(cx)
        root = Div.new.items_center.justify_center.gap(cx.theme.spacing[2]).p(cx.theme.spacing[6])
        root.child(Icon.new(@icon, size: 28, label: @title)) if @icon
        root.child(Label.new(@title, size: :lg))
        root.child(Label.new(@message, tone: :muted, size: :sm)) if @message
        root.child(@action) if @action
        root
      end

      def tui_cells(*) = [@title, @message].compact.join(" — ")
      def accessibility_node(cx) = node(:group, label: @title, children: [@action&.accessibility_node(cx)].compact)
    end
  end
end
