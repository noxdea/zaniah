# frozen_string_literal: true

require "uri"

module Zaniah
  module Platform
    module Headless
      Popup = Data.define(:labels, :enabled, :selected_index, :bounds)

      class Window
        include Appearance
        DEFAULT_CLEAR = "#181b20"

        attr_reader :content_size, :scene, :device, :dispatcher, :scale_factor, :text_runs, :pointer_position, :cursor_style, :animator, :clock, :accessibility_tree, :accessibility_revision, :frame_stats, :last_root, :frame_number, :decorations, :transparent, :min_size, :resizable, :traffic_lights, :drag_data, :drag_result, :drag_history
        attr_accessor :text_system, :ime_state, :title, :app, :devtools

        def initialize(width: 800, height: 600, title: "Zaniah UI", scale_factor: 1,
                       keymap: nil, clock: MONOTONIC_CLOCK, decorations: :native,
                       transparent: false, min_size: nil, resizable: true, traffic_lights: nil)
          raise ArgumentError, "unknown window decorations" unless %i[native hidden_titlebar none].include?(decorations)
          raise ArgumentError, "transparent must be boolean" unless transparent == true || transparent == false
          raise ArgumentError, "min_size must be a Size" unless min_size.nil? || min_size.is_a?(Size)
          raise ArgumentError, "resizable must be boolean" unless resizable == true || resizable == false
          raise ArgumentError, "traffic_lights must be a Point" unless traffic_lights.nil? || traffic_lights.is_a?(Point)
          @content_size, @scale_factor, @title = Size.new(width, height), scale_factor, title
          @decorations, @transparent, @min_size, @resizable, @traffic_lights = decorations, transparent, min_size, resizable, traffic_lights
          @scene = Scene.new
          @device = GPU::Software.new(width, height)
          @dispatcher = Input::Dispatcher.new(keymap: keymap || Input::Keymap.default_ui(clock: clock))
          @clock = clock
          @animator = Animator.new(clock: clock)
          @accessibility_tree, @accessibility_revision = Accessibility::Tree.new, 0
          @frame_stats = {fps: 0.0, frame_ms: 0.0, layout_ms: 0.0, prepaint_ms: 0.0, paint_ms: 0.0, command_count: 0}.freeze
          @state, @used_state, @text_runs = {}, {}, []
          @last_root, @frame_number = nil, 0
          @window_frame = Bounds.new(0, 0, width, height)
          @maximized = @minimized = @fullscreen = @always_on_top = false
          @dirty, @closed, @pointer_down, @cursor_style = true, false, false, :arrow
          @drag_history = []
        end

        def on_input(&block) = @on_input = block
        def on_resize(&block) = @on_resize = block
        def on_close(&block) = @on_close = block
        def on_moved(&block) = @on_moved = block
        def on_state_change(&block) = @on_state_change = block
        def on_tick(&block) = @on_tick = block
        def on_frame(&block) = @on_frame = block
        def draw(&block) = @draw = block
        def request_frame = @dirty = true
        def dirty? = @dirty
        def animation_active? = !!@animator&.active?
        def closed? = @closed
        def pointer_down? = @pointer_down
        def write_clipboard(items)
          unless items.is_a?(Array) && items.all? { |item| item.is_a?(Clipboard::Item) }
            raise TypeError, "clipboard items must be an Array of Clipboard::Item"
          end
          @clipboard_items = items.dup.freeze
        end

        def clipboard_types
          (@clipboard_items || []).flat_map(&:types).uniq.freeze
        end

        def read_clipboard(types:)
          raise TypeError, "clipboard types must be an Array" unless types.is_a?(Array)
          formats = {}
          types.each do |type|
            item = (@clipboard_items || []).find { |entry| entry.types.include?(type) }
            formats[type] = item.fetch(type) if item
          end
          Clipboard::Content.new(formats)
        end

        def clipboard
          content = read_clipboard(types: ["text/plain"])
          content.types.empty? ? "" : content.fetch("text/plain")
        end

        def clipboard=(text)
          value = text.to_s
          write_clipboard([Clipboard::Item.new("text/plain" => value)])
          value
        end
        def begin_drag(data, event: nil)
          raise TypeError, "drag source must return DragData" unless data.is_a?(DragData)
          @drag_data, @drag_result = data, nil
          @drag_move_committed = false
          @drag_history << [:begin, data, event].freeze
          data
        end

        def drag_over(types:, position:, operations: [:copy])
          event = Input::DragOver.new(types: types, position: position, operations: operations)
          @dispatcher.mouse(event)
          event.operation
        end

        def deliver_drop(content:, position:, operation: :copy, paths: nil)
          raise TypeError, "drop content must be Clipboard::Content" unless content.is_a?(Clipboard::Content)
          raise TypeError, "drop position must be a Point" unless position.is_a?(Point)
          raise ArgumentError, "invalid drop operation" unless DragData::OPERATIONS.include?(operation)
          handled = input(Input::DataDrop.new(content, position, operation))
          paths ||= file_paths_in_drop(content)
          input(Input::FileDrop.new(paths.freeze, position)) unless paths.empty?
          handled ? operation : :none
        end

        def complete_drag(position:, operation: nil, content: nil)
          raise Error, "no drag is active" unless @drag_data
          data = @drag_data
          operation ||= drag_over(types: data.types, position: position, operations: data.operations)
          raise ArgumentError, "drag operation was not offered" unless operation == :none || data.operations.include?(operation)
          operation = deliver_drop(content: content || data.content, position: position, operation: operation) unless operation == :none
          finish_drag_source(operation, position: position)
        end

        def finish_drag_source(operation, position: nil)
          raise ArgumentError, "drag operation was not offered" unless operation == :none || @drag_data&.operations&.include?(operation)
          operation = :none if operation == :move && !commit_drag_move
          @drag_result = operation
          @drag_history << [:complete, operation, position].freeze
          @drag_data = nil
          operation
        end

        def commit_drag_move
          return false unless @drag_data&.on_move
          return true if @drag_move_committed
          @drag_data.on_move.call
          @drag_move_committed = true
        rescue StandardError
          false
        end

        def file_paths_in_drop(content)
          source = content.formats["text/uri-list"]
          return [] unless source
          source.each_line.filter_map do |line|
            next if line.start_with?("#") || line.strip.empty?
            uri = URI.parse(line.strip)
            next unless uri.scheme == "file" && [nil, "", "localhost"].include?(uri.host) && uri.query.nil? && uri.fragment.nil?
            path = URI::DEFAULT_PARSER.unescape(uri.path).force_encoding(Encoding::UTF_8)
            path if path.start_with?("/") && path.valid_encoding? && !path.include?("\0")
          rescue URI::InvalidURIError
            nil
          end
        end
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
        def move_to_display(display)
          validate_display!(display)
          raise Error, "#{self.class} does not support native display placement"
        end
        def window_region_at(position)
          @dispatcher.hit_regions.reverse_each do |region|
            next unless region.contains?(position)
            owner = region.owner
            return owner.window_control_kind if owner.respond_to?(:window_control_kind) && owner.window_control_kind
            return :drag if owner.respond_to?(:window_drag_region?) && owner.window_drag_region?
            return nil
          end
          nil
        end

        def frame = @window_frame
        def frame=(bounds)
          WindowState.new(frame: bounds, display_id: nil, maximized: false, fullscreen: false)
          raise ArgumentError, "headless frame origin must be numeric" if bounds.x.nil?
          old = @window_frame
          @window_frame = bounds
          if old.width != bounds.width || old.height != bounds.height
            @suppress_state_change = true
            begin
              resize(bounds.width, bounds.height)
            ensure
              @suppress_state_change = false
            end
          end
          @on_moved&.call([bounds.x, bounds.y]) if old.x != bounds.x || old.y != bounds.y
          notify_state_change unless old == bounds
          bounds
        end
        def maximized? = @maximized
        def minimized? = @minimized
        def fullscreen? = @fullscreen
        def always_on_top? = @always_on_top
        def always_on_top=(value)
          @always_on_top = !!value
          notify_state_change
        end
        def state
          display = displays.find { |candidate| candidate.id == @display_id } || displays.find(&:primary) || displays.first
          WindowState.new(frame: frame, display_id: display&.id, maximized: @maximized, fullscreen: @fullscreen)
        end
        def maximize
          return if @maximized
          @restore_frame ||= frame
          @maximized, @minimized = true, false
          self.frame = (displays.find(&:primary) || displays.first).bounds
          notify_state_change
        end
        def minimize
          return if @minimized
          @minimized = true
          notify_state_change
        end
        def restore
          changed = @maximized || @minimized || @fullscreen
          @maximized = @minimized = @fullscreen = false
          self.frame = @restore_frame if @restore_frame
          @restore_frame = nil
          notify_state_change if changed
        end
        def toggle_fullscreen
          if @fullscreen
            restore
          else
            @restore_frame ||= frame
            @fullscreen, @minimized = true, false
            self.frame = (displays.find(&:primary) || displays.first).bounds
            notify_state_change
          end
        end
        def restore_state(saved)
          saved = WindowState.from_h(saved)
          display = displays.find { |candidate| candidate.id == saved.display_id } || displays.find(&:primary) || displays.first
          raise Error, "no display is available" unless display

          bounds = display.bounds
          requested = saved.frame
          width, height = requested.width, requested.height
          x = requested.x || bounds.x
          y = requested.y || bounds.y
          visible_x = [width, bounds.width, 48].min
          visible_y = [height, bounds.height, 32].min
          x = x.clamp(bounds.x - width + visible_x, bounds.right - visible_x)
          y = y.clamp(bounds.y, bounds.bottom - visible_y)
          @display_id = display.id
          @maximized = @minimized = @fullscreen = false
          self.frame = Bounds.new(x, y, width, height)
          if saved.maximized
            maximize
          elsif saved.fullscreen
            toggle_fullscreen
          end
          state
        end

        def popup
          if @popup_component&.open? && @popup_component.respond_to?(:popup_data)
            data = @popup_component.popup_data
            return Popup.new(labels: data[:labels], enabled: data[:enabled], selected_index: data[:selected_index], bounds: data[:bounds])
          end
          return unless @menu

          Popup.new(labels: @menu[:items].map { |label, _| label.dup.freeze }.freeze,
                    enabled: @menu[:items].map { |_, callback| !callback.nil? }.freeze,
                    selected_index: @menu[:index], bounds: popup_bounds(@menu))
        end

        def tooltip_state = @tooltip&.merge(text: @tooltip[:text].dup.freeze)&.freeze

        def resize(width, height)
          @content_size = Size.new(width, height)
          @window_frame = Bounds.new(@window_frame.x, @window_frame.y, width, height)
          @device.resize(width, height)
          @on_resize&.call(@content_size)
          request_frame
          notify_state_change unless @suppress_state_change
          true
        end

        def notify_state_change = @on_state_change&.call(state)

        def input(event)
          return if popup_input(event)
          @pointer_position = event.position if event.respond_to?(:position)
          @pointer_down = true if event.is_a?(Input::MouseDown)
          @pointer_down = false if event.is_a?(Input::MouseUp)
          @tooltip_offered = false if event.is_a?(Input::MouseMove)
          @tooltip = nil if event.is_a?(Input::MouseDown) || event.is_a?(Input::KeyDown)
          @on_input&.call(event)
          @devtools&.handle_input(event)
          handled = if event.respond_to?(:position)
            @dispatcher.mouse(event)
          elsif event.is_a?(Input::KeyDown)
            @dispatcher.key(event.keystroke)
          else
            @dispatcher.input(event)
          end
          @tooltip = nil if event.is_a?(Input::MouseMove) && !@tooltip_offered
          request_frame
          handled
        end

        def offer_tooltip(text, position:, delay: 0.5)
          @tooltip_offered = true
          return if @tooltip && @tooltip[:text] == text
          @tooltip = {text: text.to_s, position: position, at: @clock.call + delay, shown: false}
        end

        def context_menu(items, position: Point.new(0, 0))
          if items.is_a?(Zaniah::Menu)
            require "zaniah/ui" unless defined?(Zaniah::UI::ContextMenu)
          elsif !items.is_a?(Array) || !items.all? { |item| item.is_a?(Array) && item.length == 2 && item.first.is_a?(String) && (item.last.nil? || item.last.respond_to?(:call)) }
            raise ArgumentError, "menu items must be label/callback pairs or a Menu"
          end
          if defined?(Zaniah::UI::ContextMenu)
            @popup_component = Zaniah::UI::ContextMenu.new(items, anchor: position,
              dispatcher: @dispatcher, registry: app&.actions, target_focus: @dispatcher.focused)
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
          frame_started = MONOTONIC_CLOCK.call
          @text_system.scale_factor = @scale_factor if @text_system.respond_to?(:scale_factor=)
          @scene.clear
          @scene.vector_sink.size = @content_size if @scene.vector_sink&.respond_to?(:size=)
          @text_runs.clear
          @text_system.start_frame if @text_system.respond_to?(:start_frame)
          @used_state.clear
          @dispatcher.clear_hits
          cx = FrameContext.new(self)
          @animator.reduced_motion = cx.theme.motion.reduced?
          layout_started = MONOTONIC_CLOCK.call
          root = element.request_layout(cx)
          Layout::Engine.new.compute(root, width: @content_size.width, height: @content_size.height)
          layout_finished = MONOTONIC_CLOCK.call
          @animator.sample(@clock.call)
          element.prepaint(root.bounds, nil, cx)
          cx.interactivity.resolve(@dispatcher, @pointer_position, @pointer_down)
          prepaint_finished = MONOTONIC_CLOCK.call
          set_cursor(:arrow)
          element.paint(root.bounds, nil, nil, cx)
          paint_popups
          paint_finished = MONOTONIC_CLOCK.call
          overlays = [@popup_component].compact
          accessibility_changed(@accessibility_tree.root, @accessibility_tree.changes) if @accessibility_tree.update(element, cx, overlays: overlays)
          @state.delete_if { |key, _| !@used_state[key] }
          elapsed = frame_started - (@last_frame_at || frame_started)
          fps = elapsed.positive? ? 1.0 / elapsed : 0.0
          @smoothed_fps = @smoothed_fps ? @smoothed_fps * 0.9 + fps * 0.1 : fps
          @last_frame_at = frame_started
          @frame_stats = {fps: @smoothed_fps, frame_ms: (paint_finished - frame_started) * 1000,
            layout_ms: (layout_finished - layout_started) * 1000,
            prepaint_ms: (prepaint_finished - layout_finished) * 1000,
            paint_ms: (paint_finished - prepaint_finished) * 1000,
            command_count: @scene.commands.length / 4}.freeze
          @last_root = element
          @frame_number += 1
          @on_frame&.call(element, clear)
          @device.render(@scene, clear: clear) if present
          @text_system.end_frame if @text_system.respond_to?(:end_frame)
        end

        def element_state(key)
          @used_state[key] = true
          return @state[key] if @state.key?(key)
          @state[key] = yield
        end

        def accessibility_changed(root, changes)
          @accessibility_revision += 1
          Accessibility.publish(self, root, changes)
        end

        def write_png(path) = @device.write_png(path)

        private

        def validate_display!(display)
          raise ArgumentError, "expected a Zaniah::Platform::Display" unless display.is_a?(Display)
        end

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
