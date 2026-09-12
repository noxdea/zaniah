# frozen_string_literal: true

module Zaniah
  module UI
    class Button < Component
      variants size: {
        sm: ->(theme) { {height: 28, padding: [4, 10], font_size: theme.typography.size_sm} },
        md: ->(theme) { {height: 36, padding: [6, 14], font_size: theme.typography.size_md} },
        lg: ->(theme) { {height: 44, padding: [8, 18], font_size: theme.typography.size_lg} }
      }, variant: {
        primary: ->(theme) { {background: theme.colors.accent, hover: theme.colors.accent_hover, foreground: theme.colors.accent_text, border: theme.colors.accent} },
        secondary: ->(theme) { {background: theme.colors.surface, hover: theme.colors.surface_hover, foreground: theme.colors.text, border: theme.colors.border} },
        ghost: ->(theme) { {background: "#0000", hover: theme.colors.surface_hover, foreground: theme.colors.text, border: "#0000"} },
        danger: ->(theme) { {background: theme.colors.danger, hover: theme.colors.danger.darken(0.12), foreground: theme.colors.text_inverse, border: theme.colors.danger} }
      }

      attr_reader :label

      def initialize(label, size: :md, variant: :primary)
        super()
        @label, @size, @variant, @disabled, @loading = label.to_s.encode(Encoding::UTF_8), size, variant, false, false
      end

      def on_click(&block) = (@on_click = block; self)
      def disabled(value = true) = (@disabled = !!value; self)
      def loading(value = true) = (@loading = !!value; self)
      def icon(value, position: :leading)
        raise ArgumentError, "icon position must be leading or trailing" unless %i[leading trailing].include?(position)
        @icon, @icon_position = value, position
        self
      end

      def build(cx)
        @cx = cx
        style = self.class.variant_style(cx.theme, size: @size, variant: @variant)
        root = Div.new.flex_row.items_center.justify_center.gap(cx.theme.spacing[2])
          .style(height: style[:height], padding: style[:padding], background: style[:background],
            border: 1, border_color: style[:border], corner_radii: cx.theme.radii[:sm], cursor: :pointer)
          .hover(background: style[:hover]).active(opacity: 0.82)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
          .focusable(context: {in_button: true}) { |action| action == :activate && activate(nil, @cx) }
          .on_click { |event, context| activate(event, context) }
        root.disabled(@disabled || @loading)
        content = [Text.new(@loading ? "…" : @label, size: style[:font_size], color: style[:foreground])]
        content.unshift(icon_element(style[:foreground])) if @icon && @icon_position != :trailing
        content << icon_element(style[:foreground]) if @icon && @icon_position == :trailing
        root.children(content)
      end

      def tui_cells(*) = @disabled ? "( #{@label} )" : "[ #{@loading ? "…" : @label} ]"
      def accessibility_node(_cx) = node(:button, label: @label, states: {disabled: @disabled, busy: @loading}, actions: @disabled ? [] : [:press])

      protected

      def changed(_event, _cx); end

      private

      def activate(event, cx)
        return false if @disabled || @loading
        changed(event, cx)
        @on_click&.call(event, cx)
        cx&.window&.request_frame
        true
      end

      def icon_element(color)
        @icon.is_a?(Icon) ? @icon : Icon.new(@icon, size: @size == :sm ? 12 : 16, color: color)
      end
    end

    class IconButton < Button
      def initialize(icon, label:, **options)
        super(label, **options)
        icon(icon)
      end

      def build(cx)
        super.style(padding: 0, width: {sm: 28, md: 36, lg: 44}.fetch(@size))
      end

      def tui_cells(*) = @disabled ? "(#{Icon::GLYPHS[@icon] || @label})" : "[#{Icon::GLYPHS[@icon] || @label}]"
    end

    class ToggleButton < Button
      attr_reader :value

      def initialize(label, value: false, **options)
        super(label, **options)
        @value = !!value
      end

      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        root = super
        root.selected(@value).style(background: cx.theme.colors.surface_pressed) if @value
        root
      end

      def accessibility_node(_cx) = node(:button, label: @label, value: @value, states: {pressed: @value, disabled: @disabled}, actions: @disabled ? [] : [:press])

      protected

      def changed(event, cx)
        @value = !@value
        @on_change&.call(@value, event, cx)
      end
    end

    class ButtonGroup < Component
      def initialize(*buttons)
        super()
        @buttons = buttons.flatten
      end

      def child(button) = (@buttons << button; self)
      def build(cx) = Div.new.flex_row.items_center.gap(cx.theme.spacing[1]).children(@buttons)
      def tui_cells(*) = @buttons.map(&:tui_cells).join(" ")
      def accessibility_node(cx) = node(:group, children: @buttons.filter_map { |button| button.accessibility_node(cx) })
    end

    class Checkbox < Component
      attr_reader :value

      def initialize(label, value: false, disabled: false)
        super()
        @label, @value, @disabled = label.to_s, normalize(value), !!disabled
      end

      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)

      def build(cx)
        @cx = cx
        mark = @value == :mixed ? "−" : @value ? "✓" : ""
        box = Div.new.w(18).h(18).items_center.justify_center.rounded(3).border(1)
          .border_color(@value ? cx.theme.colors.accent : cx.theme.colors.border)
          .bg(@value ? cx.theme.colors.accent : cx.theme.colors.surface)
          .child(Text.new(mark, size: 13, color: cx.theme.colors.accent_text))
        Div.new.flex_row.items_center.gap(cx.theme.spacing[2]).cursor(:pointer)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
          .focusable(context: {in_button: true}) { |action| action == :activate && toggle(nil, @cx) }
          .on_click { |event, context| toggle(event, context) }
          .disabled(@disabled).children([box, Text.new(@label, color: cx.theme.colors.text)])
      end

      def tui_cells(*) = "[#{@value == :mixed ? "-" : @value ? "x" : " "}] #{@label}"
      def accessibility_node(_cx) = node(:checkbox, label: @label, value: @value, states: {checked: @value == true, mixed: @value == :mixed, disabled: @disabled}, actions: @disabled ? [] : [:toggle])

      private

      def normalize(value)
        raise ArgumentError, "checkbox value must be true, false, or mixed" unless [true, false, :mixed].include?(value)
        value
      end

      def toggle(event, cx)
        return false if @disabled
        @value = @value == true ? false : true
        @on_change&.call(@value, event, cx)
        cx&.window&.request_frame
        true
      end
    end

    class Radio < Checkbox
      def build(cx)
        @cx = cx
        dot = Div.new.w(18).h(18).items_center.justify_center.rounded(9).border(1)
          .border_color(@value ? cx.theme.colors.accent : cx.theme.colors.border)
          .child(Div.new.w(8).h(8).rounded(4).bg(@value ? cx.theme.colors.accent : "#0000"))
        Div.new.flex_row.items_center.gap(cx.theme.spacing[2]).cursor(:pointer)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
          .focusable(context: {in_button: true}) { |action| action == :activate && select(nil, @cx) }
          .on_click { |event, context| select(event, context) }
          .disabled(@disabled).children([dot, Text.new(@label, color: cx.theme.colors.text)])
      end

      def tui_cells(*) = "(#{@value ? "o" : " "}) #{@label}"
      def accessibility_node(_cx) = node(:radio, label: @label, value: @value, states: {checked: @value == true, disabled: @disabled}, actions: @disabled ? [] : [:select])

      private

      def select(event, cx)
        return false if @disabled
        @value = true
        @on_change&.call(true, event, cx)
        cx&.window&.request_frame
        true
      end
    end

    class RadioGroup < Component
      attr_reader :value

      def initialize(options, value: nil)
        super()
        @options, @value = options.to_a, value
      end

      def on_change(&block) = (@on_change = block; self)

      def build(cx)
        radios = @options.map do |label, value = label|
          Radio.new(label.to_s, value: @value == value).on_change do |_checked, event, context|
            @value = value
            @on_change&.call(value, event, context)
          end
        end
        @radios = radios
        Div.new.gap(cx.theme.spacing[2]).children(radios)
      end

      def tui_cells(*) = (@radios || []).map(&:tui_cells).join(" ")
      def accessibility_node(cx) = node(:radiogroup, value: @value, children: (@radios || []).map { |radio| radio.accessibility_node(cx) })
    end

    class Switch < Checkbox
      def build(cx)
        @cx = cx
        knob = Div.new.w(16).h(16).rounded(8).bg(cx.theme.colors.text_inverse)
        track = Div.new.w(36).h(20).p(2).rounded(10).bg(@value ? cx.theme.colors.accent : cx.theme.colors.border)
          .style(align_items: @value ? :end : :start).child(knob)
        Div.new.flex_row.items_center.gap(cx.theme.spacing[2]).cursor(:pointer)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
          .focusable(context: {in_button: true}) { |action| action == :activate && send(:toggle, nil, @cx) }
          .on_click { |event, context| send(:toggle, event, context) }.disabled(@disabled)
          .children([track, Text.new(@label, color: cx.theme.colors.text)])
      end

      def tui_cells(*) = "[#{@value ? "on " : "off"}] #{@label}"
      def accessibility_node(_cx) = node(:switch, label: @label, value: @value, states: {checked: @value == true, disabled: @disabled}, actions: @disabled ? [] : [:toggle])
    end

    class Slider < Component
      attr_reader :value

      def initialize(value: 0, min: 0, max: 100, step: 1, label: nil, disabled: false)
        super()
        @min, @max, @step, @label, @disabled = Float(min), Float(max), Float(step), label&.to_s, !!disabled
        raise ArgumentError, "slider max must exceed min and step must be positive" unless @max > @min && @step.positive?
        @value = snap(value)
      end

      def on_change(&block) = (@on_change = block; self)
      def disabled(value = true) = (@disabled = !!value; self)

      def build(cx)
        @cx = cx
        percent_value = ratio * 100
        track = Div.new.w_full.h(4).rounded(2).bg(cx.theme.colors.border)
          .child(Div.new.style(position: :absolute, left: 0, top: 0, width: percent(percent_value), height: 4, background: cx.theme.colors.accent, corner_radii: 2))
          .child(Div.new.style(position: :absolute, left: percent(percent_value), top: -6, width: 16, height: 16, margin_left: -8,
            background: cx.theme.colors.accent, corner_radii: 8))
        Div.new.w(160).h(24).justify_center.cursor(:pointer).disabled(@disabled)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
          .focusable(context: {in_slider: true}) { |action| adjust(action, @cx) }
          .on_mouse_down { |event, context| point(event, context) }
          .on_drag { |event, context| point(event, context) }.child(track)
      end

      def tui_cells(*)
        filled = (ratio * 10).round
        "#{@label && "#{@label} "}[#{"=" * filled}#{"-" * (10 - filled)}] #{@value}"
      end

      def accessibility_node(_cx) = node(:slider, label: @label, value: @value, states: {disabled: @disabled}, actions: @disabled ? [] : %i[increment decrement])

      protected

      def set_value(value, event, cx)
        value = snap(value)
        return false if @disabled || value == @value
        @value = value
        @on_change&.call(@value, event, cx)
        cx&.window&.request_frame
        true
      end

      def snap(value)
        value = Float(value).clamp(@min, @max)
        (@min + ((value - @min) / @step).round * @step).clamp(@min, @max)
      end

      def ratio = (@value - @min) / (@max - @min)

      private

      def point(event, cx)
        set_value(@min + (event.position.x - @bounds.x).clamp(0, @bounds.width).to_f / [@bounds.width, 1].max * (@max - @min), event, cx)
        :capture
      end

      def adjust(action, cx)
        target = case action
        when :decrement then @value - @step
        when :increment then @value + @step
        when :decrement_page then @value - @step * 10
        when :increment_page then @value + @step * 10
        when :minimum then @min
        when :maximum then @max
        else return false
        end
        set_value(target, nil, cx)
      end
    end

    class RangeSlider < Slider
      attr_reader :upper_value

      def initialize(value: [25, 75], **options)
        lower, upper = value
        super(value: lower, **options)
        @upper_value = snap(upper)
        raise ArgumentError, "range slider values must be ordered" if @upper_value < @value
      end

      def build(cx)
        @cx = cx
        lower, upper = [ratio, (@upper_value - @min) / (@max - @min)]
        track = Div.new.w_full.h(4).rounded(2).bg(cx.theme.colors.border)
          .child(Div.new.style(position: :absolute, left: percent(lower * 100), top: 0,
            width: percent((upper - lower) * 100), height: 4, background: cx.theme.colors.accent, corner_radii: 2))
        [lower, upper].each do |position|
          track.child(Div.new.style(position: :absolute, left: percent(position * 100), top: -6,
            width: 16, height: 16, margin_left: -8, background: cx.theme.colors.accent, corner_radii: 8))
        end
        Div.new.w(160).h(24).justify_center.cursor(:pointer).disabled(@disabled)
          .focus_visible(ring: Ring.new(2, cx.theme.colors.ring, 2))
          .focusable(context: {in_slider: true}) { |action| range_action(action, @cx) }
          .on_mouse_down { |event, context| range_point(event, context) }
          .on_drag { |event, context| range_point(event, context) }.child(track)
      end

      def accessibility_node(_cx) = node(:slider, label: @label, value: [@value, @upper_value], states: {disabled: @disabled}, actions: @disabled ? [] : %i[increment decrement])
      def tui_cells(*) = "#{@label && "#{@label} "}[#{@value}..#{@upper_value}]"

      private

      def range_point(event, cx)
        candidate = @min + (event.position.x - @bounds.x).clamp(0, @bounds.width).to_f / [@bounds.width, 1].max * (@max - @min)
        @active_thumb = (candidate - @value).abs <= (candidate - @upper_value).abs ? :lower : :upper if event.is_a?(Input::MouseDown)
        set_range_value(@active_thumb, candidate, event, cx)
        @active_thumb = nil if event.is_a?(Input::MouseUp)
        :capture
      end

      def range_action(action, cx)
        delta = case action
        when :decrement then -@step
        when :increment then @step
        when :decrement_page then -@step * 10
        when :increment_page then @step * 10
        when :minimum then return set_range_value(:lower, @min, nil, cx)
        when :maximum then return set_range_value(:upper, @max, nil, cx)
        else return false
        end
        set_range_value(@active_thumb || :lower, (@active_thumb == :upper ? @upper_value : @value) + delta, nil, cx)
      end

      def set_range_value(which, candidate, event, cx)
        candidate = snap(candidate)
        candidate = [candidate, @upper_value].min if which == :lower
        candidate = [candidate, @value].max if which == :upper
        return false if @disabled || (which == :lower ? candidate == @value : candidate == @upper_value)
        which == :lower ? @value = candidate : @upper_value = candidate
        @on_change&.call([@value, @upper_value], event, cx)
        cx&.window&.request_frame
        true
      end
    end

    class ProgressBar < Component
      attr_reader :value

      def initialize(value: nil, min: 0, max: 100, label: nil)
        super()
        @value, @min, @max, @label = value&.to_f, Float(min), Float(max), label&.to_s
        raise ArgumentError, "progress max must exceed min" unless @max > @min
      end

      def build(cx)
        track = Div.new.w(160).h(8).overflow_hidden.rounded(4).bg(cx.theme.colors.border)
        track.child(Div.new.h_full.w(percent(ratio * 100)).bg(cx.theme.colors.accent)) if @value
        track
      end

      def tui_cells(*) = @value ? "[#{"=" * (ratio * 10).round}#{"-" * (10 - (ratio * 10).round)}]" : "[···]"
      def accessibility_node(_cx) = node(:progressbar, label: @label, value: @value, states: {busy: @value.nil?})

      protected

      def ratio = @value ? ((@value - @min) / (@max - @min)).clamp(0, 1) : 0
    end

    class Spinner < Component
      def initialize(label: "Loading", size: 16)
        super()
        @label, @size = label.to_s, size
      end

      def build(cx) = Text.new("◌", size: @size, color: cx.theme.colors.accent)
      def tui_cells(*) = "◌ #{@label}"
      def accessibility_node(_cx) = node(:progressbar, label: @label, states: {busy: true})
    end

    class Meter < ProgressBar
      def initialize(value:, low: nil, high: nil, optimum: nil, **options)
        super(value: value, **options)
        @low, @high, @optimum = low&.to_f, high&.to_f, optimum&.to_f
      end

      def accessibility_node(_cx) = node(:meter, label: @label, value: @value, states: {low: @low, high: @high, optimum: @optimum})
    end
  end
end
