# frozen_string_literal: true

require "fiddle"

module Zaniah
  module Accessibility
    module Windows
      module Provider
        P = Fiddle::TYPE_VOIDP
        I = Fiddle::TYPE_INT
        U = Fiddle::TYPE_UINT
        N = Fiddle::TYPE_INTPTR_T
        S_OK = 0
        E_NOINTERFACE = -2_147_467_262
        E_FAIL = -2_147_467_259
        UIA_APPEND_RUNTIME_ID = -1

        GUIDS = {
          unknown: "00000000-0000-0000-c000-000000000046",
          simple: "d6dd68d1-86fd-4332-8666-9abedea2d24c",
          fragment: "f7063da8-8359-439c-9297-bbc5299a7d87",
          root: "620ce2a5-ab8f-40a9-86cb-de3c75599b58",
          invoke: "54fcb24b-e18e-47a2-b4d3-eccbe77599a2",
          range: "36dc7aef-33e6-4691-afe1-2be7274b3d33"
        }.transform_values { |value| first, second, third, fourth, fifth = value.split("-"); [first.hex, second.hex, third.hex].pack("Vvv") + [fourth + fifth].pack("H*") }.freeze

        CONTROL_TYPES = {
          button: 50_000, checkbox: 50_002, switch: 50_002, combobox: 50_003, textbox: 50_004,
          searchbox: 50_004, link: 50_005, image: 50_006, listitem: 50_007, list: 50_008,
          listbox: 50_008, menu: 50_009, menubar: 50_010, menuitem: 50_011,
          progressbar: 50_012, meter: 50_012, radio: 50_013, slider: 50_015, status: 50_017,
          tabpanel: 50_018, tab: 50_019, text: 50_020, heading: 50_020, toolbar: 50_021,
          tooltip: 50_022, tree: 50_023, treeitem: 50_024, group: 50_026, radiogroup: 50_026,
          form: 50_026, table: 50_036, row: 50_029, cell: 50_029, columnheader: 50_035,
          dialog: 50_032, navigation: 50_033, separator: 50_038
        }.freeze

        class Bridge
          attr_reader :window, :tree, :root_provider

          def initialize(window)
            @window, @providers = window, {}
          end

          def update(root)
            @tree = NativeTree.new(root, previous: @tree)
            @tree.each do |entry|
              provider = @providers[entry.runtime_id] ||= Element.new(self)
              provider.entry = entry
            end
            @root_provider = @providers[@tree.root.runtime_id]
          end

          def provider(entry) = entry && @providers[entry.runtime_id]
          def entry(path) = @tree[path]

          def raise_events(events)
            events.each do |event|
              provider = %i[structure layout].include?(event.kind) ? @root_provider : provider(@tree[event.path]) || @root_provider
              id = Windows::AUTOMATION_EVENTS[event.kind]
              core.fn(:UiaRaiseAutomationEvent, [P, I], I).call(provider.pointer(:simple), id) if id
            end
          rescue Fiddle::DLError
            nil
          end

          def screen_bounds(entry)
            bounds = @tree.bounds(entry)
            point = [(bounds.x * scale).round, (bounds.y * scale).round].pack("l2")
            user.fn(:ClientToScreen, [P, P], I).call(@window.handle, point)
            x, y = point.unpack("l2")
            [x.to_f, y.to_f, bounds.width * scale, bounds.height * scale]
          rescue NoMethodError
            [bounds.x, bounds.y, bounds.width, bounds.height]
          end

          def provider_at(x, y)
            point = [x.round, y.round].pack("l2")
            user.fn(:ScreenToClient, [P, P], I).call(@window.handle, point)
            px, py = point.unpack("l2")
            provider(@tree.hit(Point.new(px / scale, py / scale)))
          rescue NoMethodError
            provider(@tree.hit(Point.new(x, y)))
          end

          def focused_provider = provider(@tree.focused(@window)) || @root_provider

          def return_provider(wparam, lparam)
            core.fn(:UiaReturnRawElementProvider, [P, N, N, P], N)
              .call(@window.handle, wparam, lparam, @root_provider.pointer(:simple))
          end

          def host_provider(output)
            core.fn(:UiaHostProviderFromHwnd, [P, P], I).call(@window.handle, output)
          end

          def bstr(value)
            bytes = value.to_s.encode("UTF-16LE").b + "\0\0".b
            ole.fn(:SysAllocString, [P], P).call(Fiddle::Pointer[bytes])
          end

          def safe_array(values)
            array = ole.fn(:SafeArrayCreateVector, [Fiddle::TYPE_USHORT, Fiddle::TYPE_LONG, U], P).call(3, 0, values.length)
            data = [0].pack("J")
            return 0 if array.to_i.zero? || ole.fn(:SafeArrayAccessData, [P, P], I).call(array, data) != S_OK
            Fiddle::Pointer.new(data.unpack1("J"))[0, values.length * 4] = values.pack("l*")
            ole.fn(:SafeArrayUnaccessData, [P], I).call(array)
            array
          end

          private

          def scale = @window.scale_factor || 1.0
          def user = @window.instance_variable_get(:@user)
          def core = (@core ||= Zaniah::FFI::Library.new("UIAutomationCore.dll"))
          def ole = (@ole ||= Zaniah::FFI::Library.new("oleaut32.dll"))
        end

        class Element
          INTERFACES = {}
          class << self
            attr_reader :vtables, :closures

            def install
              return if @vtables
              @closures = []
              unknown = [closure(I, [P, P, P]) { |this, iid, output| interface(this).query(iid, output) },
                closure(U, [P]) { |this| interface(this).add_ref }, closure(U, [P]) { |this| interface(this).release }]
              simple = unknown + [closure(I, [P, P]) { |_this, output| write_int(output, 1) },
                closure(I, [P, I, P]) { |this, pattern, output| interface(this).pattern(pattern, output) },
                closure(I, [P, I, P]) { |this, property, output| interface(this).property(property, output) },
                closure(I, [P, P]) { |this, output| interface(this).host(output) }]
              fragment = unknown + [closure(I, [P, I, P]) { |this, direction, output| interface(this).navigate(direction, output) },
                closure(I, [P, P]) { |this, output| interface(this).runtime_id(output) },
                closure(I, [P, P]) { |this, output| interface(this).bounding_rectangle(output) },
                closure(I, [P, P]) { |_this, output| write_pointer(output, 0) },
                closure(I, [P]) { |this| interface(this).set_focus },
                closure(I, [P, P]) { |this, output| interface(this).fragment_root(output) }]
              root = unknown + [closure(I, [P, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE, P]) { |this, x, y, output| interface(this).from_point(x, y, output) },
                closure(I, [P, P]) { |this, output| interface(this).focus(output) }]
              invoke = unknown + [closure(I, [P]) { |this| interface(this).invoke }]
              range = unknown + [closure(I, [P, Fiddle::TYPE_DOUBLE]) { |this, value| interface(this).set_range_value(value) },
                closure(I, [P, P]) { |this, output| interface(this).range_property(:value, output) },
                closure(I, [P, P]) { |this, output| interface(this).range_property(:readonly, output) },
                closure(I, [P, P]) { |this, output| interface(this).range_property(:maximum, output) },
                closure(I, [P, P]) { |this, output| interface(this).range_property(:minimum, output) },
                closure(I, [P, P]) { |this, output| interface(this).range_property(:large_change, output) },
                closure(I, [P, P]) { |this, output| interface(this).range_property(:small_change, output) }]
              @vtables = {simple: vtable(simple), fragment: vtable(fragment), root: vtable(root),
                invoke: vtable(invoke), range: vtable(range)}.freeze
            end

            def closure(result, arguments, &block)
              value = Fiddle::Closure::BlockCaller.new(result, arguments) do |*values|
                block.call(*values)
              rescue StandardError
                result == I ? E_FAIL : 1
              end
              @closures << value
              value
            end

            def vtable(functions)
              pointer = Fiddle::Pointer.malloc(functions.length * Fiddle::SIZEOF_VOIDP)
              pointer[0, functions.length * Fiddle::SIZEOF_VOIDP] = functions.map(&:to_i).pack("J*")
              pointer
            end

            def interface(pointer) = INTERFACES.fetch(pointer.to_i)
            def write_pointer(output, value) = (Fiddle::Pointer.new(output)[0, Fiddle::SIZEOF_VOIDP] = [value.to_i].pack("J"); S_OK)
            def write_int(output, value) = (Fiddle::Pointer.new(output)[0, 4] = [value].pack("l"); S_OK)
          end

          attr_accessor :entry
          attr_reader :bridge

          def initialize(bridge)
            self.class.install
            @bridge, @references, @interfaces = bridge, 1, {}
            %i[simple fragment root invoke range].each do |kind|
              pointer = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
              pointer[0, Fiddle::SIZEOF_VOIDP] = [self.class.vtables.fetch(kind).to_i].pack("J")
              @interfaces[kind] = pointer
              INTERFACES[pointer.to_i] = self
            end
          end

          def pointer(kind) = @interfaces.fetch(kind).to_i

          def query(iid, output)
            requested = GUIDS.key(Fiddle::Pointer.new(iid)[0, 16])
            requested = :simple if requested == :unknown
            supported = requested && (requested != :root || @entry.parent.nil?) &&
              (requested != :invoke || invokable?) && (requested != :range || range?)
            return self.class.write_pointer(output, 0) && E_NOINTERFACE unless supported
            add_ref
            self.class.write_pointer(output, pointer(requested))
          end

          def add_ref = (@references += 1)
          def release = (@references = [@references - 1, 1].max)

          def pattern(pattern, output)
            kind = pattern == 10_000 && invokable? ? :invoke : pattern == 10_003 && range? ? :range : nil
            return self.class.write_pointer(output, 0) unless kind
            add_ref
            self.class.write_pointer(output, pointer(kind))
          end

          def property(property, output)
            variant = Fiddle::Pointer.new(output)
            variant[0, 16] = "\0" * 16
            case property
            when 30_003 then variant_i4(variant, CONTROL_TYPES.fetch(@entry.node.role, 50_025))
            when 30_005 then variant_bstr(variant, @entry.node.label || @entry.node.value&.to_s || @entry.node.role.to_s)
            when 30_008 then variant_bool(variant, @bridge.focused_provider.equal?(self))
            when 30_009 then variant_bool(variant, focusable?)
            when 30_010 then variant_bool(variant, !@entry.node.states[:disabled])
            when 30_011
              id = @entry.node.id
              variant_bstr(variant, id.nil? ? @entry.runtime_id : id)
            when 30_012 then variant_bstr(variant, "Zaniah")
            when 30_016, 30_017 then variant_bool(variant, true)
            when 30_022 then variant_bool(variant, @bridge.tree.bounds(@entry).empty?)
            when 30_024 then variant_bstr(variant, "Zaniah")
            end
            S_OK
          end

          def host(output) = @entry.parent ? self.class.write_pointer(output, 0) : @bridge.host_provider(output)

          def navigate(direction, output)
            target = case direction
            when 0 then @entry.parent
            when 1, 2
              siblings = @entry.parent&.children || []
              index = siblings.index(@entry)
              index && siblings[index + (direction == 1 ? 1 : -1)] if index && (direction == 1 || index.positive?)
            when 3 then @entry.children.first
            when 4 then @entry.children.last
            end
            provider = @bridge.provider(target)
            provider&.add_ref
            self.class.write_pointer(output, provider&.pointer(:fragment) || 0)
          end

          def runtime_id(output)
            array = @bridge.safe_array([UIA_APPEND_RUNTIME_ID, @entry.runtime_id])
            self.class.write_pointer(output, array)
          end

          def bounding_rectangle(output)
            Fiddle::Pointer.new(output)[0, 32] = @bridge.screen_bounds(@entry).pack("d4")
            S_OK
          end

          def set_focus
            bounds = @bridge.tree.bounds(@entry)
            Accessibility.focus_at(@bridge.window, Point.new(bounds.x + bounds.width / 2.0, bounds.y + bounds.height / 2.0))
            S_OK
          end

          def fragment_root(output)
            root = @bridge.root_provider
            root.add_ref
            self.class.write_pointer(output, root.pointer(:root))
          end

          def from_point(x, y, output)
            provider = @bridge.provider_at(x, y) || @bridge.root_provider
            provider.add_ref
            self.class.write_pointer(output, provider.pointer(:fragment))
          end

          def focus(output)
            provider = @bridge.focused_provider
            provider.add_ref
            self.class.write_pointer(output, provider.pointer(:fragment))
          end

          def invoke
            actions = @entry.node.role == :treeitem ? %i[select collapse expand] : %i[press toggle select sort expand collapse dismiss]
            action = actions.find { |candidate| @entry.node.actions.include?(candidate) }
            Accessibility.perform(@bridge.window, @entry.node, action, bounds: @bridge.tree.bounds(@entry)) if action
            S_OK
          end

          def set_range_value(value)
            Accessibility.assign(@bridge.window, @entry.node, value) ? S_OK : E_FAIL
          end

          def range_property(name, output)
            values = {value: @entry.node.value, readonly: 0, maximum: @entry.node.states.fetch(:maximum, 1.0),
              minimum: @entry.node.states.fetch(:minimum, 0.0), large_change: @entry.node.states.fetch(:large_change, 0.1),
              small_change: @entry.node.states.fetch(:small_change, 0.01)}
            pointer = Fiddle::Pointer.new(output)
            name == :readonly ? pointer[0, 4] = [values[name]].pack("l") : pointer[0, 8] = [Float(values[name])].pack("d")
            S_OK
          end

          private

          def invokable? = @entry.node.actions.any? { |action| %i[press toggle select sort expand collapse dismiss].include?(action) }
          def range? = @entry.node.value.is_a?(Numeric) &&
            @entry.node.states.key?(:minimum) && @entry.node.states.key?(:maximum) &&
            (@entry.node.actions & %i[increment decrement]).any?
          def focusable? = !@entry.node.states[:disabled] && (!@entry.node.actions.empty? || %i[textbox searchbox slider combobox].include?(@entry.node.role))
          def variant_i4(pointer, value) = (pointer[0, 2] = [3].pack("v"); pointer[8, 4] = [value].pack("l"))
          def variant_bool(pointer, value) = (pointer[0, 2] = [11].pack("v"); pointer[8, 2] = [value ? -1 : 0].pack("s"))
          def variant_bstr(pointer, value) = (pointer[0, 2] = [8].pack("v"); pointer[8, Fiddle::SIZEOF_VOIDP] = [@bridge.bstr(value)].pack("J"))
        end
      end
    end
  end
end
