# frozen_string_literal: true

require_relative "clipboard_data"

module Zaniah
  module Platform
    module Mac
      class Window < Headless::Window
        def displays = Mac.displays
        attr_reader :handle, :view, :layer

        def initialize(gpu: :metal, **options)
          super(**options)
          App.instance
          self.class.install_classes
          style_mask = decorations == :none ? 0 : (resizable ? 15 : 7)
          style_mask |= 1 << 15 if decorations == :hidden_titlebar
          @handle = O.send(O.alloc("NSWindow"), "initWithContentRect:styleMask:backing:defer:",
                           [0, 0, content_size.width, content_size.height], style_mask, 2, 0,
                           args: [:rect, :ulong, :ulong, :bool])
          raise Error, "NSWindow creation failed" if @handle.zero?
          O.send(@handle, "setReleasedWhenClosed:", 0, args: [:bool], result: :void)
          if decorations == :hidden_titlebar
            O.send(@handle, "setTitlebarAppearsTransparent:", 1, args: [:bool], result: :void)
            O.send(@handle, "setTitleVisibility:", 1, args: [:long], result: :void)
          end
          O.send(@handle, "setMinSize:", [min_size.width, min_size.height], args: [:size], result: :void) if min_size
          unless traffic_lights.nil?
            3.times do |index|
              button = O.send(@handle, "standardWindowButton:", index, args: [:ulong])
              O.send(button, "setFrameOrigin:", [traffic_lights.x + index * 20, traffic_lights.y], args: [:point], result: :void) unless button.zero?
            end
          end
          if transparent
            O.send(@handle, "setOpaque:", 0, args: [:bool], result: :void)
            O.send(@handle, "setBackgroundColor:", O.send(O.klass("NSColor"), "clearColor"), args: [:pointer], result: :void)
          end
          @view = O.send(O.alloc("ZaniahNativeView"), "initWithFrame:", [0, 0, content_size.width, content_size.height], args: [:rect])
          @delegate = O.new("ZaniahWindowDelegate")
          WINDOWS[@handle] = WINDOWS[@view] = WINDOWS[@delegate] = self
          O.send(@view, "setAutoresizingMask:", 18, args: [:ulong], result: :void)
          O.send(@handle, "setContentView:", @view, args: [:pointer], result: :void)
          O.send(@handle, "setDelegate:", @delegate, args: [:pointer], result: :void)
          O.send(@handle, "setAcceptsMouseMovedEvents:", 1, args: [:bool], result: :void)
          O.send(@handle, "makeFirstResponder:", @view, args: [:pointer], result: :bool)
          types = [O.string("NSFilenamesPboardType"), O.string("public.file-url")].pack("J2")
          list = O.send(O.klass("NSArray"), "arrayWithObjects:count:", Fiddle::Pointer[types], 2, args: [:pointer, :ulong])
          O.send(@view, "registerForDraggedTypes:", list, args: [:pointer], result: :void)
          self.title = @title
          O.send(@handle, "center", result: :void)
          @scale_factor = O.send(@handle, "backingScaleFactor", result: :double)
          @device.release
          @device = create_device(gpu)
          O.send(@handle, "makeKeyAndOrderFront:", 0, args: [:pointer], result: :void)
        end

        def self.install_classes
          O.subclass("ZaniahNativeView", "NSView", protocols: ["NSTextInputClient"]) do |klass|
            O.method(klass, "acceptsFirstResponder", result: :bool, encoding: "B@:") { 1 }
            O.method(klass, "isFlipped", result: :bool, encoding: "B@:") { 1 }
            O.method(klass, "viewDidChangeEffectiveAppearance", encoding: "v@:") do |receiver, _|
              WINDOWS[receiver]&.native_callback { WINDOWS[receiver].appearance_changed }
            end
            %w[draggingEntered: draggingUpdated:].each do |name|
              O.method(klass, name, args: [:pointer], result: :ulong, encoding: "Q@:@") { 1 }
            end
            O.method(klass, "performDragOperation:", args: [:pointer], result: :bool, encoding: "B@:@") do |receiver, _, dragging|
              WINDOWS[receiver]&.native_callback { WINDOWS[receiver].file_drop(dragging) } ? 1 : 0
            end
            O.method(klass, "performKeyEquivalent:", args: [:pointer], result: :bool, encoding: "B@:@") do |receiver, _, event|
              WINDOWS[receiver]&.native_callback { WINDOWS[receiver].perform_key_equivalent(event) } ? 1 : 0
            end
            %w[keyDown: keyUp: flagsChanged: mouseDown: mouseUp: rightMouseDown: rightMouseUp: otherMouseDown: otherMouseUp: mouseMoved: mouseDragged: rightMouseDragged: otherMouseDragged: scrollWheel:].each do |name|
              O.method(klass, name, args: [:pointer], encoding: "v@:@") do |receiver, _, event|
                WINDOWS[receiver]&.native_callback { WINDOWS[receiver].native_input(name, event) }
              end
            end
            O.method(klass, "insertText:replacementRange:", args: [:pointer, :range], encoding: "v@:@{_NSRange=QQ}") do |receiver, _, value, _range|
              WINDOWS[receiver]&.native_callback { WINDOWS[receiver].commit_text(value) }
            end
            O.method(klass, "setMarkedText:selectedRange:replacementRange:", args: [:pointer, :range, :range], encoding: "v@:@{_NSRange=QQ}{_NSRange=QQ}") do |receiver, _, value, selection, _replacement|
              WINDOWS[receiver]&.native_callback { WINDOWS[receiver].marked_text(value, selection) }
            end
            O.method(klass, "unmarkText", encoding: "v@:") { |receiver, _| WINDOWS[receiver]&.marked_text(0, [0, 0]) }
            O.method(klass, "hasMarkedText", result: :bool, encoding: "B@:") { |receiver, _| WINDOWS[receiver]&.composing? ? 1 : 0 }
            O.method(klass, "markedRange", result: :range, encoding: "{_NSRange=QQ}@:") { |receiver, _| WINDOWS[receiver]&.marked_range || [NS_NOT_FOUND, 0] }
            O.method(klass, "selectedRange", result: :range, encoding: "{_NSRange=QQ}@:") { |receiver, _| WINDOWS[receiver]&.selected_range || [0, 0] }
            O.method(klass, "validAttributesForMarkedText", result: :pointer, encoding: "@@:") { O.send(O.klass("NSArray"), "array") }
            O.method(klass, "attributedSubstringForProposedRange:actualRange:", args: [:range, :pointer], result: :pointer, encoding: "@@:{_NSRange=QQ}^{_NSRange=QQ}") { 0 }
            O.method(klass, "characterIndexForPoint:", args: [:point], result: :ulong, encoding: "Q@:{CGPoint=dd}") { 0 }
            O.method(klass, "firstRectForCharacterRange:actualRange:", args: [:range, :pointer], result: :rect, encoding: "{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}") do |receiver, _, range, actual|
              Fiddle::Pointer.new(actual)[0, 16] = range.pack("Q2") unless actual.zero?
              WINDOWS[receiver]&.candidate_rect || [0, 0, 0, 0]
            end
            O.method(klass, "doCommandBySelector:", args: [:pointer], encoding: "v@::") { nil }
          end
          O.subclass("ZaniahWindowDelegate", "NSObject", protocols: ["NSWindowDelegate"]) do |klass|
            O.method(klass, "contextMenuAction:", args: [:pointer], encoding: "v@:@") do |receiver, _, item|
              WINDOWS[receiver]&.native_callback { WINDOWS[receiver].context_action(O.send(item, "tag", result: :long)) }
            end
            %w[windowDidResize: windowDidChangeBackingProperties: windowDidMove:].each do |name|
              O.method(klass, name, args: [:pointer], encoding: "v@:@") do |receiver, _, _notification|
                WINDOWS[receiver]&.native_callback { WINDOWS[receiver].native_resize(moved: name == "windowDidMove:") }
              end
            end
            %w[windowDidMiniaturize: windowDidDeminiaturize: windowDidEnterFullScreen: windowDidExitFullScreen:].each do |name|
              O.method(klass, name, args: [:pointer], encoding: "v@:@") do |receiver, _, _notification|
                WINDOWS[receiver]&.native_callback { WINDOWS[receiver].native_state_changed }
              end
            end
            O.method(klass, "windowShouldClose:", args: [:pointer], result: :bool, encoding: "B@:@") do |receiver, _, _window|
              WINDOWS[receiver]&.native_callback { WINDOWS[receiver].close }
              0
            end
          end
        end

        def create_device(backend)
          case backend
          when :metal
            require_relative "../../gpu/metal"
            @layer ||= O.new("CAMetalLayer")
            O.send(@view, "setWantsLayer:", 1, args: [:bool], result: :void)
            O.send(@view, "setLayer:", @layer, args: [:pointer], result: :void)
            GPU::Metal.new(self)
          when :opengl, :gl
            require_relative "../../gpu/open_gl"
            O.send(@view, "setWantsBestResolutionOpenGLSurface:", 1, args: [:bool], result: :void)
            attributes = [99, 0x4100, 5, 8, 24, 11, 8, 0].pack("I*")
            format = O.send(O.alloc("NSOpenGLPixelFormat"), "initWithAttributes:", Fiddle::Pointer[attributes], args: [:pointer])
            raise Error, "OpenGL 4.1 core pixel format unavailable" if format.zero?
            @gl_context = O.send(O.alloc("NSOpenGLContext"), "initWithFormat:shareContext:", format, 0, args: [:pointer, :pointer])
            O.release(format)
            O.send(@gl_context, "setView:", @view, args: [:pointer], result: :void)
            interval = [1].pack("i")
            O.send(@gl_context, "setValues:forParameter:", Fiddle::Pointer[interval], 222, args: [:pointer, :int], result: :void)
            GPU::OpenGL.new(self, library: FFI::Library.new("/System/Library/Frameworks/OpenGL.framework/OpenGL"))
          else raise ArgumentError, "unsupported Cocoa GPU backend #{backend}"
          end
        end
        def make_current = O.send(@gl_context, "makeCurrentContext", result: :void)
        def swap_buffers = O.send(@gl_context, "flushBuffer", result: :void)
        def title=(title)
          super
          O.send(@handle, "setTitle:", O.string(title), args: [:pointer], result: :void) if @handle
        end
        def tick(poll_events: true)
          App.instance.poll if poll_events
          raise @native_error if @native_error
          super()
        end
        def run
          until closed?
            App.instance.poll(wait: dirty? || animation_active? ? 0 : 0.05)
            tick(poll_events: false)
          end
        end
        def close
          return false unless super
          Accessibility.close(self)
          WINDOWS.delete_if { |_, window| window.equal?(self) }
          O.send(@handle, "setDelegate:", 0, args: [:pointer], result: :void)
          O.send(@handle, "close", result: :void)
          [@gl_context, @layer, @delegate, @view, @handle].compact.each { |object| O.release(object) }
          true
        end
        def native_callback
          yield
        rescue StandardError => error
          @native_error = error
        end
        def native_resize(moved: false)
          return if closed?
          bounds = O.send(@view, "bounds", result: :rect)
          @scale_factor = O.send(@handle, "backingScaleFactor", result: :double)
          resize(bounds[2], bounds[3]) if bounds[2].positive? && bounds[3].positive? && (bounds[2] != content_size.width || bounds[3] != content_size.height)
          O.send(@gl_context, "update", result: :void) if @gl_context
          @on_moved&.call([frame.x, frame.y]) if moved
          notify_state_change if moved
        end
        def native_state_changed = notify_state_change
        def frame
          x, y, width, height = O.send(@handle, "frame", result: :rect)
          primary_height = displays.find(&:primary)&.bounds&.height || height
          Bounds.new(x, primary_height - y - height, width, height)
        end
        def frame=(bounds)
          WindowState.new(frame: bounds, display_id: nil, maximized: false, fullscreen: false)
          raise ArgumentError, "macOS frame origin must be numeric" if bounds.x.nil?
          primary_height = displays.find(&:primary)&.bounds&.height || bounds.height
          O.send(@handle, "setFrame:display:", [bounds.x, primary_height - bounds.y - bounds.height, bounds.width, bounds.height], 1,
            args: [:rect, :bool], result: :void)
          bounds
        end
        def maximized? = O.send(@handle, "isZoomed", result: :bool) != 0
        def minimized? = O.send(@handle, "isMiniaturized", result: :bool) != 0
        def fullscreen? = (O.send(@handle, "styleMask", result: :ulong) & (1 << 14)) != 0
        def always_on_top? = O.send(@handle, "level", result: :long) != 0
        def always_on_top=(value)
          O.send(@handle, "setLevel:", value ? 3 : 0, args: [:long], result: :void)
          notify_state_change
        end
        def state
          screen = O.send(@handle, "screen")
          description = O.send(screen, "deviceDescription") unless screen.zero?
          identifier = O.send(description, "objectForKey:", O.string("NSScreenNumber"), args: [:pointer]) if description
          id = O.send(identifier, "unsignedIntValue", result: :uint) if identifier && !identifier.zero?
          WindowState.new(frame: frame, display_id: id, maximized: maximized?, fullscreen: fullscreen?)
        end
        def maximize
          O.send(@handle, "performZoom:", 0, args: [:pointer], result: :void) unless maximized?
        end
        def minimize
          O.send(@handle, "miniaturize:", 0, args: [:pointer], result: :void) unless minimized?
        end
        def restore
          O.send(@handle, "deminiaturize:", 0, args: [:pointer], result: :void) if minimized?
          O.send(@handle, "performZoom:", 0, args: [:pointer], result: :void) if maximized?
          toggle_fullscreen if fullscreen?
        end
        def toggle_fullscreen = O.send(@handle, "toggleFullScreen:", 0, args: [:pointer], result: :void)
        def move_to_display(display)
          validate_display!(display)
          screens = O.send(O.klass("NSScreen"), "screens")
          count = O.send(screens, "count", result: :ulong)
          screen = Array.new(count) { |index| O.send(screens, "objectAtIndex:", index, args: [:ulong]) }.find do |candidate|
            description = O.send(candidate, "deviceDescription")
            identifier = O.send(description, "objectForKey:", O.string("NSScreenNumber"), args: [:pointer])
            O.send(identifier, "unsignedIntValue", result: :uint) == display.id
          end
          raise Error, "display is no longer available" unless screen

          x, y, _width, height = O.send(screen, "frame", result: :rect)
          O.send(@handle, "setFrameTopLeftPoint:", [x, y + height], args: [:point], result: :void)
          true
        end

        KEYS = {36 => "enter", 48 => "tab", 49 => "space", 51 => "backspace", 53 => "esc", 117 => "delete", 115 => "home", 119 => "end", 116 => "pageup", 121 => "pagedown", 123 => "left", 124 => "right", 125 => "down", 126 => "up"}.freeze
        def key_stroke(event, modifiers)
          code = O.send(event, "keyCode", result: :uint)
          character = O.text(O.send(event, "charactersIgnoringModifiers")).downcase
          key = KEYS.fetch(code, character)
          (modifiers + [key]).join("-") unless key.empty?
        end
        def perform_key_equivalent(event)
          flags = O.send(event, "modifierFlags", result: :ulong)
          modifiers = [[18, "ctrl"], [19, "alt"], [17, "shift"], [20, "cmd"]].filter_map { |bit, key| key unless (flags & (1 << bit)).zero? }
          return false if (modifiers & %w[cmd ctrl alt]).empty?
          return false if composing? && (modifiers & %w[cmd ctrl]).empty?
          stroke = key_stroke(event, modifiers)
          return false unless stroke
          action = @dispatcher.key(stroke)
          return false unless action
          input_event = Input::KeyDown.new(stroke, O.send(event, "isARepeat", result: :bool) != 0)
          @tooltip = nil
          @on_input&.call(input_event)
          @devtools&.handle_input(input_event)
          request_frame
          true
        end
        def native_input(name, event)
          flags = O.send(event, "modifierFlags", result: :ulong)
          modifiers = [[18, "ctrl"], [19, "alt"], [17, "shift"], [20, "cmd"]].filter_map { |bit, key| key unless (flags & (1 << bit)).zero? }
          if name.start_with?("key")
            stroke = key_stroke(event, modifiers)
            unless stroke.nil? || (name == "keyDown:" && composing? && (modifiers & %w[cmd ctrl]).empty?)
              input(name == "keyDown:" ? Input::KeyDown.new(stroke, O.send(event, "isARepeat", result: :bool) != 0) : Input::KeyUp.new(stroke))
            end
            if name == "keyDown:" && (modifiers & %w[cmd ctrl]).empty?
              context = O.send(@view, "inputContext")
              O.send(context, "handleEvent:", event, args: [:pointer], result: :bool)
            end
          elsif name != "flagsChanged:"
            x, y = O.send(event, "locationInWindow", result: :point)
            position = Point.new(x, content_size.height - y)
            button = [:left, :right, :middle].fetch(O.send(event, "buttonNumber", result: :long), :other)
            if name == "mouseDown:" && decorations != :native && window_region_at(position) == :drag
              O.send(@handle, "performWindowDragWithEvent:", event, args: [:pointer], result: :void)
              return
            end
            input(case name
            when /Down:/ then Input::MouseDown.new(position, button, modifiers, O.send(event, "clickCount", result: :long))
            when /Up:/ then Input::MouseUp.new(position, button, modifiers)
            when "scrollWheel:"
              Input::ScrollWheel.new(position, Point.new(-O.send(event, "scrollingDeltaX", result: :double), -O.send(event, "scrollingDeltaY", result: :double)), O.send(event, "phase", result: :ulong), modifiers)
            else Input::MouseMove.new(position, modifiers)
            end)
          end
        end

        def cocoa_text(value)
          value = O.send(value, "string") if O.send(value, "isKindOfClass:", O.klass("NSAttributedString"), args: [:pointer], result: :bool) != 0
          O.text(value)
        end
        def commit_text(value)
          text = cocoa_text(value)
          @marked, @marked_selection = "", [0, 0]
          input(Input::Composition.new("", [0, 0]))
          input(Input::TextInput.new(text)) unless text.empty?
        end
        def marked_text(value, selection)
          @marked, @marked_selection = cocoa_text(value), selection
          input(Input::Composition.new(@marked, selection))
        end
        def composing? = @marked && !@marked.empty?
        def marked_range = composing? ? [0, @marked.encode("UTF-16LE").bytesize / 2] : [NS_NOT_FOUND, 0]
        def selected_range = @marked_selection || [0, 0]
        def candidate_rect
          bounds = @ime_state.respond_to?(:bounds) ? @ime_state.bounds : @ime_state
          bounds = Bounds.new(0, 0, 1, 20) unless bounds.is_a?(Bounds)
          O.send(@handle, "convertRectToScreen:", [bounds.x, content_size.height - bounds.bottom, bounds.width, bounds.height], args: [:rect], result: :rect)
        end
        def ime_state=(value)
          @ime_state = value
          O.send(O.send(@view, "inputContext"), "invalidateCharacterCoordinates", result: :void) if @view
        end
        def clipboard = read_clipboard(types: ["text/plain"]).formats.fetch("text/plain", "")
        def clipboard=(text)
          value = text.to_s
          write_clipboard([Clipboard::Item.new("text/plain" => value)])
          value
        end
        def pasteboard = O.send(O.klass("NSPasteboard"), "generalPasteboard")
        def write_clipboard(items)
          stored = super
          board = pasteboard
          if stored.empty?
            O.send(board, "clearContents", result: :long)
            return stored
          end

          first, *remaining = stored
          formats, file_urls = pasteboard_formats(first)
          types = cocoa_array(formats.keys.map { |name| O.string(name) })
          O.send(board, "declareTypes:owner:", types, 0, args: [:pointer, :pointer], result: :long)
          formats.each do |name, data|
            raise Error, "NSPasteboard refused #{name}" unless set_pasteboard_data(board, name, data)
          end

          native_items = []
          begin
            file_urls.drop(1).each do |url|
              item = O.new("NSPasteboardItem")
              native_items << item
              raise Error, "NSPasteboard refused file URL" unless set_pasteboard_data(item, "public.file-url", url)
            end
            remaining.each do |source|
              native_formats, urls = pasteboard_formats(source)
              item = O.new("NSPasteboardItem")
              native_items << item
              native_formats.each do |name, data|
                raise Error, "NSPasteboard refused #{name}" unless set_pasteboard_data(item, name, data)
              end
              urls.drop(1).each do |url|
                file_item = O.new("NSPasteboardItem")
                native_items << file_item
                raise Error, "NSPasteboard refused file URL" unless set_pasteboard_data(file_item, "public.file-url", url)
              end
            end
            if native_items.any?
              raise Error, "NSPasteboard writeObjects failed" if O.send(board, "writeObjects:", cocoa_array(native_items), args: [:pointer], result: :bool).zero?
            end
          ensure
            native_items.each { |item| O.release(item) }
          end
          stored
        end
        def read_clipboard(types:)
          raise TypeError, "clipboard types must be an Array" unless types.is_a?(Array)
          board = pasteboard
          items = pasteboard_items(board)
          formats = {}
          types.each do |type|
            data = if type == "text/uri-list"
              read_pasteboard_data(items, ClipboardData.native_type(type)) || pasteboard_file_urls(items).join("\r\n").then { |value| value.empty? ? nil : value + "\r\n" }
            else
              read_pasteboard_data(items, ClipboardData.native_type(type))
            end
            formats[type] = type.start_with?("text/") ? data.force_encoding(Encoding::UTF_8).scrub : data if data
          end
          Clipboard::Content.new(formats)
        end
        def clipboard_types
          board = pasteboard
          pasteboard_items(board).flat_map do |item|
            types = O.send(item, "types")
            cocoa_objects(types).filter_map { |name| ClipboardData.mime_type(O.text(name)) }
          end.uniq.freeze
        end
        def pasteboard_formats(item)
          formats = item.formats.to_h { |type, data| [ClipboardData.native_type(type), data] }
          urls = item.types.include?("text/uri-list") ? ClipboardData.file_urls(item.fetch("text/uri-list")) : []
          formats["public.file-url"] = urls.first if urls.any?
          [formats, urls]
        end
        def set_pasteboard_data(receiver, type, bytes)
          data = O.send(O.klass("NSData"), "dataWithBytes:length:", Fiddle::Pointer[bytes], bytes.bytesize, args: [:pointer, :ulong])
          O.send(receiver, "setData:forType:", data, O.string(type), args: [:pointer, :pointer], result: :bool) != 0
        end
        def cocoa_array(objects)
          packed = objects.pack("J*")
          O.send(O.klass("NSArray"), "arrayWithObjects:count:", Fiddle::Pointer[packed], objects.length, args: [:pointer, :ulong])
        end
        def cocoa_objects(array)
          return [] if array.zero?
          Array.new(O.send(array, "count", result: :ulong)) { |index| O.send(array, "objectAtIndex:", index, args: [:ulong]) }
        end
        def pasteboard_items(board) = cocoa_objects(O.send(board, "pasteboardItems"))
        def read_pasteboard_data(items, type)
          items.each do |item|
            data = O.send(item, "dataForType:", O.string(type), args: [:pointer])
            next if data.zero?
            size = O.send(data, "length", result: :ulong)
            pointer = O.send(data, "bytes")
            return Fiddle::Pointer.new(pointer)[0, size].b
          end
          nil
        end
        def pasteboard_file_urls(items)
          items.filter_map do |item|
            value = O.send(item, "stringForType:", O.string("public.file-url"), args: [:pointer])
            O.text(value) unless value.zero?
          end
        end
        def clipboard_paths = pasteboard_paths(pasteboard)
        def pasteboard_paths(board)
          list = O.send(board, "propertyListForType:", O.string("NSFilenamesPboardType"), args: [:pointer])
          paths = Array.new(O.send(list, "count", result: :ulong)) { |i| O.text(O.send(list, "objectAtIndex:", i, args: [:ulong])) }
          return paths unless paths.empty?
          items = O.send(board, "pasteboardItems")
          Array.new(O.send(items, "count", result: :ulong)) do |i|
            item = O.send(items, "objectAtIndex:", i, args: [:ulong])
            value = O.send(item, "stringForType:", O.string("public.file-url"), args: [:pointer])
            next if value.zero?
            url = O.send(O.klass("NSURL"), "URLWithString:", value, args: [:pointer])
            O.text(O.send(url, "path")) if O.send(url, "isFileURL", result: :bool) != 0
          end.compact
        end
        def file_drop(dragging)
          paths = pasteboard_paths(O.send(dragging, "draggingPasteboard"))
          return false if paths.empty?
          x, y = O.send(dragging, "draggingLocation", result: :point)
          input(Input::FileDrop.new(paths.freeze, Point.new(x, content_size.height - y)))
          true
        end
        def appearance
          name = O.text(O.send(O.send(@view, "effectiveAppearance"), "name"))
          name.include?("Dark") ? :dark : :light
        end
        def reduced_motion?
          workspace = O.send(O.klass("NSWorkspace"), "sharedWorkspace")
          selector = O.selector("accessibilityDisplayShouldReduceMotion")
          return false if O.send(workspace, "respondsToSelector:", selector, args: [:pointer], result: :bool).zero?
          O.send(workspace, "accessibilityDisplayShouldReduceMotion", result: :bool) != 0
        end
        def on_appearance(&block) = @on_appearance = block
        def appearance_changed
          @on_appearance&.call(appearance)
          request_frame
        end
        def tooltip=(text)
          O.send(@view, "setToolTip:", O.string(text), args: [:pointer], result: :void)
        end
        def context_action(index) = @context_actions&.fetch(index)&.call
        def context_menu(items, position: Point.new(0, 0))
          return super if defined?(Zaniah::UI::ContextMenu) && !items.is_a?(Zaniah::Menu)
          menu = O.new("NSMenu")
          O.send(menu, "setAutoenablesItems:", 0, args: [:bool], result: :void)
          @context_actions = []
          if items.is_a?(Zaniah::Menu)
            options = {registry: app&.actions, keymap: dispatcher.keymap, platform: :mac}
            append_context_model_items(menu, items, items.resolve(**options), options)
          else
            items.each do |label, action|
              item = O.send(O.alloc("NSMenuItem"), "initWithTitle:action:keyEquivalent:", O.string(label), O.selector("contextMenuAction:"), O.string(""), args: [:pointer] * 3)
              O.send(item, "setTarget:", @delegate, args: [:pointer], result: :void)
              O.send(item, "setTag:", @context_actions.length, args: [:long], result: :void)
              O.send(item, "setEnabled:", action ? 1 : 0, args: [:bool], result: :void)
              O.send(menu, "addItem:", item, args: [:pointer], result: :void)
              @context_actions << action
              O.release(item)
            end
          end
          O.send(menu, "popUpMenuPositioningItem:atLocation:inView:", 0, [position.x, position.y], @view, args: [:pointer, :point, :pointer], result: :bool)
        ensure
          @context_actions = nil
          O.release(menu) if menu
        end
        def append_context_model_items(menu, model, items, options)
          items.each do |entry|
            next if %i[app_menu window_menu].include?(entry.role)
            if entry.separator?
              O.send(menu, "addItem:", O.send(O.klass("NSMenuItem"), "separatorItem"), args: [:pointer], result: :void)
              next
            end
            item = O.send(O.alloc("NSMenuItem"), "initWithTitle:action:keyEquivalent:",
              O.string(entry.title.to_s), entry.submenu? ? 0 : O.selector("contextMenuAction:"), O.string(""), args: [:pointer] * 3)
            if entry.submenu?
              submenu = O.send(O.alloc("NSMenu"), "initWithTitle:", O.string(entry.title.to_s), args: [:pointer])
              O.send(submenu, "setAutoenablesItems:", 0, args: [:bool], result: :void)
              append_context_model_items(submenu, model, model.children_for(entry, **options), options)
              O.send(item, "setSubmenu:", submenu, args: [:pointer], result: :void)
              O.release(submenu)
            else
              enabled = dispatcher.available?(entry.action) == :enabled
              O.send(item, "setTag:", @context_actions.length, args: [:long], result: :void)
              O.send(item, "setTarget:", @delegate, args: [:pointer], result: :void)
              O.send(item, "setEnabled:", enabled ? 1 : 0, args: [:bool], result: :void)
              O.send(item, "setState:", dispatcher.checked?(entry.action) ? 1 : 0, args: [:long], result: :void)
              @context_actions << (enabled ? -> { dispatcher.perform(entry.action, source: :menu) } : nil)
            end
            O.send(menu, "addItem:", item, args: [:pointer], result: :void)
            O.release(item)
          end
        end
        def prompt_for_paths(multiple: false, directories: false, save: false)
          panel = O.send(O.klass(save ? "NSSavePanel" : "NSOpenPanel"), save ? "savePanel" : "openPanel")
          unless save
            O.send(panel, "setAllowsMultipleSelection:", multiple ? 1 : 0, args: [:bool], result: :void)
            O.send(panel, "setCanChooseDirectories:", directories ? 1 : 0, args: [:bool], result: :void)
          end
          return [] unless O.send(panel, "runModal", result: :long) == 1
          urls = save ? [O.send(panel, "URL")] : begin
            list = O.send(panel, "URLs")
            Array.new(O.send(list, "count", result: :ulong)) { |i| O.send(list, "objectAtIndex:", i, args: [:ulong]) }
          end
          urls.map { |url| O.text(O.send(url, "path")) }
        end
        def cursor_style=(style)
          selector = {arrow: "arrowCursor", text: "IBeamCursor", pointer: "pointingHandCursor", crosshair: "crosshairCursor", resize_horizontal: "resizeLeftRightCursor", resize_vertical: "resizeUpDownCursor"}.fetch(style)
          O.send(O.send(O.klass("NSCursor"), selector), "set", result: :void)
        end
        def open_url(url)
          object = O.send(O.klass("NSURL"), "URLWithString:", O.string(url), args: [:pointer])
          O.send(O.send(O.klass("NSWorkspace"), "sharedWorkspace"), "openURL:", object, args: [:pointer], result: :bool) != 0
        end
      end
    end
  end
end
