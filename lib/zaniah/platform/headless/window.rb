# frozen_string_literal: true

module Zaniah
  module Platform
    module Headless
      Popup = Data.define(:labels, :enabled, :selected_index, :bounds)

      class Window
        include Appearance
        DEFAULT_CLEAR = "#181b20"

        attr_reader :content_size, :scene, :device, :dispatcher, :scale_factor, :text_runs, :pointer_position, :cursor_style, :animator, :clock
        attr_accessor :text_system, :ime_state, :title, :app

        def initialize(width: 800, height: 600, title: "Zaniah UI", scale_factor: 1,
                       keymap: nil, clock: MONOTONIC_CLOCK)
          @content_size, @scale_factor, @title = Size.new(width, height), scale_factor, title
          @scene = Scene.new
          @device = GPU::Software.new(width, height)
          @dispatcher = Input::Dispatcher.new(keymap: keymap || Input::Keymap.default_ui(clock: clock))
          @clock = clock
          @animator = Animator.new(clock: clock)
          @state, @used_state, @text_runs = {}, {}, []
          @dirty, @closed, @pointer_down, @cursor_style = true, false, false, :arrow
        end

        def on_input(&block) = @on_input = block
        def on_resize(&block) = @on_resize = block
        def on_close(&block) = @on_close = block
        def on_moved(&block) = @on_moved = block
        def on_tick(&block) = @on_tick = block
        def on_frame(&block) = @on_frame = block
        def draw(&block) = @draw = block
        def request_frame = @dirty = true
        def dirty? = @dirty
        def animation_active? = !!@animator&.active?
        def closed? = @closed
        def pointer_down? = @pointer_down
        def set_cursor(style)
          raise ArgumentError, "unknown cursor #{style}" unless %i[arrow text pointer crosshair resize_horizontal resize_vertical].include?(style)
          return style if @cursor_style == style
          self.cursor_style = style
          @cursor_style = style
        end
        def cursor_style=(style)
          @cursor_style = style
        end
        def displays = [Display.new(0, "Headless", Bounds.new(0, 0, @content_size.width, @content_size.height), @scale_factor, true)]

        def popup
          if @popup_component.respond_to?(:popup_data)
            data = @popup_component.popup_data
            return Popup.new(labels: data[:labels], enabled: data[:enabled], selected_index: data[:selected_index], bounds: data[:bounds])
          end
          return unless @menu

          Popup.new(labels: @menu[:items].map { |label, _| label.dup.freeze }.freeze,
                    enabled: @menu[:items].map { |_, callback| !callback.nil? }.freeze,
                    selected_index: @menu[:index], bounds: popup_bounds(@menu))
        end

        def resize(width, height)
          @content_size = Size.new(width, height)
          @device.resize(width, height)
          @on_resize&.call(@content_size)
          request_frame
        end

        def input(event)
          return if popup_input(event)
          @pointer_position = event.position if event.respond_to?(:position)
          @pointer_down = true if event.is_a?(Input::MouseDown)
          @pointer_down = false if event.is_a?(Input::MouseUp)
          @tooltip_offered = false if event.is_a?(Input::MouseMove)
          @tooltip = nil if event.is_a?(Input::MouseDown) || event.is_a?(Input::KeyDown)
          @on_input&.call(event)
          if event.respond_to?(:position)
            @dispatcher.mouse(event)
          elsif event.is_a?(Input::KeyDown)
            @dispatcher.key(event.keystroke)
          else
            @dispatcher.input(event)
          end
          @tooltip = nil if event.is_a?(Input::MouseMove) && !@tooltip_offered
          request_frame
        end

        def offer_tooltip(text, position:, delay: 0.5)
          @tooltip_offered = true
          return if @tooltip && @tooltip[:text] == text
          @tooltip = {text: text.to_s, position: position, at: @clock.call + delay, shown: false}
        end

        def context_menu(items, position: Point.new(0, 0))
          raise ArgumentError, "menu items must be label/callback pairs" unless items.is_a?(Array) && items.all? { |item| item.is_a?(Array) && item.length == 2 && item.first.is_a?(String) && (item.last.nil? || item.last.respond_to?(:call)) }
          if defined?(Zaniah::UI::ContextMenu)
            @popup_component = Zaniah::UI::ContextMenu.new(items, anchor: position)
            @menu = nil
            @tooltip = nil
            request_frame
            return @popup_component
          end
          @menu = {items: items.map(&:dup), position: position, index: items.index { |_, callback| callback } || 0}
          @tooltip = nil
          request_frame
        end

        def close
          return if @closed
          return false if @on_close && @on_close.call == false
          @closed = true
          @device.release
          @text_system.close if @text_system.respond_to?(:close)
          true
        end

        def tick
          @on_tick&.call
          if @tooltip && !@tooltip[:shown] && @clock.call >= @tooltip[:at]
            @tooltip[:shown] = true
            request_frame
          end
          request_frame if @animator&.active?
          return unless @dirty && !@closed
          @dirty = false
          result = @draw&.call(self)
          if result.respond_to?(:request_layout) && result.respond_to?(:prepaint) && result.respond_to?(:paint)
            render(result)
          elsif result.is_a?(Scene)
            @device.render(result)
          end
          request_frame if @animator&.active?
        end

        def render(element, clear: DEFAULT_CLEAR, present: true)
          @text_system.scale_factor = @scale_factor if @text_system.respond_to?(:scale_factor=)
          @scene.clear
          @text_runs.clear
          @text_system.start_frame if @text_system.respond_to?(:start_frame)
          @used_state.clear
          @dispatcher.clear_hits
          cx = FrameContext.new(self)
          root = element.request_layout(cx)
          Layout::Engine.new.compute(root, width: @content_size.width, height: @content_size.height)
          @animator.reduced_motion = cx.theme.motion.reduced?
          @animator.sample(@clock.call)
          element.prepaint(root.bounds, nil, cx)
          cx.interactivity.resolve(@dispatcher, @pointer_position, @pointer_down)
          set_cursor(:arrow)
          element.paint(root.bounds, nil, nil, cx)
          paint_popups
          @state.delete_if { |key, _| !@used_state[key] }
          @on_frame&.call(element, clear)
          @device.render(@scene, clear: clear) if present
          @text_system.end_frame if @text_system.respond_to?(:end_frame)
        end

        def element_state(key)
          @used_state[key] = true
          return @state[key] if @state.key?(key)
          @state[key] = yield
        end

        def write_png(path) = @device.write_png(path)

        private

        def popup_input(event)
          if @popup_component
            unless @popup_component.open?
              @popup_component = nil
              return false
            end
            @pointer_position = event.position if event.respond_to?(:position)
            @pointer_down = true if event.is_a?(Input::MouseDown)
            @pointer_down = false if event.is_a?(Input::MouseUp)
            if event.respond_to?(:position)
              @dispatcher.mouse(event)
            elsif event.is_a?(Input::KeyDown)
              @dispatcher.key(event.keystroke)
            else
              @dispatcher.input(event)
            end
            request_frame
            return true
          end
          return false unless @menu
          if event.is_a?(Input::KeyDown)
            key = Input::Keystroke.normalize(event.keystroke)
            if key == "esc"
              @menu = nil
            elsif key == "enter"
              callback = @menu[:items][@menu[:index]]&.last
              @menu = nil
              callback&.call
            elsif ["up", "down"].include?(key) && !@menu[:items].empty?
              step = key == "up" ? -1 : 1
              @menu[:items].length.times do
                @menu[:index] = (@menu[:index] + step) % @menu[:items].length
                break if @menu[:items][@menu[:index]].last
              end
            end
          elsif event.is_a?(Input::MouseDown)
            box = popup_bounds(@menu)
            index = ((event.position.y - box.y - 4) / 26).floor
            callback = @menu[:items][index]&.last if box.contains?(event.position) && index >= 0
            @menu = nil
            callback&.call
          elsif event.is_a?(Input::MouseMove)
            box = popup_bounds(@menu)
            index = ((event.position.y - box.y - 4) / 26).floor
            @menu[:index] = index if box.contains?(event.position) && index.between?(0, @menu[:items].length - 1)
          end
          request_frame
          true
        end

        def popup_bounds(menu)
          width = [menu[:items].map { |label, _| label.length * 8 + 24 }.max || 80, @content_size.width].min
          height = [menu[:items].length * 26 + 8, @content_size.height].min
          Bounds.new(menu[:position].x.clamp(0, @content_size.width - width), menu[:position].y.clamp(0, @content_size.height - height), width, height)
        end

        def popup_text(text, x, y, color)
          if @text_system
            line = @text_system.layout_line(text, size: 13)
            @text_system.paint_line(@scene, line, x: x, y: y + line.ascent, color: color)
          end
          @text_runs << [x, y, text, color]
        end

        def paint_popups
          if @popup_component
            paint_popup_component(@popup_component)
          elsif @menu
            box = popup_bounds(@menu)
            @scene.layer(Scene::LAYER_POPUP) do
              @scene.quad(box.x, box.y, box.width, box.height, color: "#202936", radius: 4, border_width: 1, border_color: "#526176")
              @scene.clip(box) do
                @menu[:items].each_with_index do |(label, callback), index|
                  y = box.y + 4 + index * 26
                  @scene.quad(box.x + 3, y, box.width - 6, 26, color: "#345477") if index == @menu[:index]
                  popup_text(label, box.x + 12, y + 4, callback ? "#edf2f7" : "#8997aa")
                end
              end
            end
          elsif @tooltip && @tooltip[:shown] && defined?(Zaniah::UI::Tooltip)
            paint_popup_component(Zaniah::UI::Tooltip.new(@tooltip[:text], anchor: @tooltip[:position]))
          elsif @tooltip && @tooltip[:shown]
            text = @tooltip[:text]
            position = @tooltip[:position]
            width = [text.length * 8 + 20, @content_size.width].min
            x, y = position.x.clamp(0, @content_size.width - width), (position.y + 20).clamp(0, [@content_size.height - 30, 0].max)
            @scene.layer(Scene::LAYER_TOOLTIP) do
              @scene.quad(x, y, width, 28, color: "#202936", radius: 4, border_width: 1, border_color: "#526176")
              @scene.clip(Bounds.new(x, y, width, 28)) { popup_text(text, x + 10, y + 5, "#edf2f7") }
            end
          end
        end

        def paint_popup_component(component)
          cx = FrameContext.new(self)
          root = component.request_layout(cx)
          Layout::Engine.new.compute(root, width: @content_size.width, height: @content_size.height)
          component.prepaint(root.bounds, nil, cx)
          component.paint(root.bounds, nil, nil, cx)
        end
      end
    end
  end
end
