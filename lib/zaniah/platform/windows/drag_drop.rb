# frozen_string_literal: true

require_relative "../../ffi/com"

module Zaniah
  module Platform
    module Windows
      # OLE drag-and-drop interfaces. All callbacks and vtables stay pinned for
      # the lifetime of the window; the native side only owns STGMEDIUM blocks.
      class DragDrop
        P, I, U, Q = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_LONG_LONG
        E_NOINTERFACE = 0x80004002
        E_NOTIMPL = 0x80004001
        DV_E_FORMATETC = 0x80040064
        S_FALSE = 1
        GUIDS = {
          unknown: [0, 0, 0xc0, 0, 0, 0, 0, 0, 0, 0, 0x46].pack("L< S< S< C8"),
          data: [0x10e, 0, 0, 0xc0, 0, 0, 0, 0, 0, 0, 0x46].pack("L< S< S< C8"),
          source: [0x121, 0, 0, 0xc0, 0, 0, 0, 0, 0, 0, 0x46].pack("L< S< S< C8"),
          target: [0x122, 0, 0, 0xc0, 0, 0, 0, 0, 0, 0, 0x46].pack("L< S< S< C8"),
          enumerator: [0x103, 0, 0, 0xc0, 0, 0, 0, 0, 0, 0, 0x46].pack("L< S< S< C8")
        }.freeze
        EFFECTS = {copy: 1, move: 2, link: 4}.freeze

        class Interface
          attr_reader :pointer, :references

          def initialize(owner, kind, methods)
            @owner, @kind, @references = owner, kind, 1
            signatures = [
              [[P, P], ->(_this, iid, out) { query_interface(iid, out) }],
              [[], ->(*) { @references += 1 }],
              [[], ->(*) { @references -= 1 }],
              *methods
            ]
            @callbacks = signatures.map do |types, body|
              Fiddle::Closure::BlockCaller.new(I, [P, *types]) do |*arguments|
                body.call(*arguments)
              rescue StandardError => error
                @owner.report(error)
                0x80004005
              end
            end
            @table = Fiddle::Pointer.malloc(@callbacks.length * Fiddle::SIZEOF_VOIDP)
            @table[0, @callbacks.length * Fiddle::SIZEOF_VOIDP] = @callbacks.map(&:to_i).pack("J*")
            @object = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
            @object[0, Fiddle::SIZEOF_VOIDP] = [@table.to_i].pack("J")
            @pointer = @object.to_i
          end

          def query_interface(iid, out)
            bytes = Fiddle::Pointer.new(iid)[0, 16]
            if [GUIDS[:unknown], GUIDS.fetch(@kind)].include?(bytes)
              Fiddle::Pointer.new(out)[0, 8] = [@pointer].pack("J")
              @references += 1
              0
            else
              Fiddle::Pointer.new(out)[0, 8] = [0].pack("J")
              E_NOINTERFACE
            end
          end
        end

        def initialize(window)
          @window = window
          @ole = FFI::Library.new("ole32.dll")
          @kernel = FFI::Library.new("kernel32.dll")
          status = @ole.fn(:OleInitialize, [P], I).call(0)
          FFI::COM.check(status)
          @initialized = true
          @target = Interface.new(self, :target, [
            [[P, U, Q, P], ->(_this, data, _keys, point, effect) { enter(data, point, effect) }],
            [[U, Q, P], ->(_this, _keys, point, effect) { over(point, effect) }],
            [[], ->(*) { @types = @formats = []; @source_effects = 0; 0 }],
            [[P, U, Q, P], ->(_this, data, _keys, point, effect) { drop(data, point, effect) }]
          ])
          @types = @formats = []
          FFI::COM.check(@ole.fn(:RegisterDragDrop, [P, P], I).call(window.handle, @target.pointer))
          @registered = true
        rescue StandardError
          close
          raise
        end

        def close
          @ole.fn(:RevokeDragDrop, [P], I).call(@window.handle) if @registered
          @registered = false
          @ole.fn(:OleUninitialize, [], Fiddle::TYPE_VOID).call if @initialized
          @initialized = false
        end

        def report(error) = @window.instance_variable_set(:@native_error, error)

        def screen_position(point)
          bytes = [point & 0xffffffff, (point >> 32) & 0xffffffff].pack("L<2")
          @window.instance_variable_get(:@user).fn(:ScreenToClient, [P, P], I).call(@window.handle, bytes)
          x, y = bytes.unpack("l<2")
          Point.new(x / @window.scale_factor, y / @window.scale_factor)
        end

        def offered_formats(data)
          pointer = [0].pack("J")
          result = []
          if FFI::COM.vcall(data, 8, [U, P], I, 1, pointer).zero?
            enumeration = pointer.unpack1("J")
            begin
              256.times do
                descriptor, fetched = "\0".b * 32, [0].pack("L<")
                break unless FFI::COM.vcall(enumeration, 3, [U, P, P], I, 1, descriptor, fetched).zero?
                format = descriptor.unpack1("S<")
                result << format if (descriptor[24, 4].unpack1("L<") & 1) != 0
              end
            ensure
              FFI::COM.release(enumeration)
            end
          end
          names = ["text/plain", "text/html", "image/png", "text/uri-list"]
          names.concat(@window.dispatcher.hit_regions.flat_map { |hit| hit.owner.respond_to?(:drop_types) ? hit.owner.drop_types : [] })
          names.uniq.each do |name|
            format = @window.clipboard_payload(name, "").first
            result << format if FFI::COM.vcall(data, 5, [P], I, format_descriptor(format)).zero?
          end
          result.uniq
        end

        def enter(data, point, effect)
          @formats = offered_formats(data)
          @types = @formats.filter_map { |format| @window.clipboard_type_name(format) }
          @source_effects = Fiddle::Pointer.new(effect)[0, 4].unpack1("L<")
          over(point, effect)
        end

        def over(point, effect)
          mask = Fiddle::Pointer.new(effect)[0, 4].unpack1("L<")
          mask = @source_effects if mask.zero?
          operations = EFFECTS.filter_map { |name, bit| name unless (mask & bit).zero? }
          chosen = operations.empty? ? :none : @window.drag_over(types: @types, position: screen_position(point), operations: operations)
          chosen = :copy if chosen == :none && @types.include?("text/uri-list") && operations.include?(:copy)
          Fiddle::Pointer.new(effect)[0, 4] = [EFFECTS.fetch(chosen, 0)].pack("L<")
          @operation = chosen
          0
        end

        def drop(data, point, effect)
          over(point, effect)
          return 0 if @operation == :none
          formats = {}
          paths = []
          @formats.each do |format|
            type = @window.clipboard_type_name(format)
            next unless type
            bytes, file_paths = read_format(data, format)
            paths.concat(file_paths) if file_paths
            formats[type] = bytes if bytes
          end
          if formats.empty?
            Fiddle::Pointer.new(effect)[0, 4] = [0].pack("L<")
            return 0
          end
          result = @window.deliver_drop(content: Clipboard::Content.new(formats), position: screen_position(point), operation: @operation, paths: paths)
          Fiddle::Pointer.new(effect)[0, 4] = [EFFECTS.fetch(result, 0)].pack("L<")
          0
        ensure
          @types = @formats = []
        end

        def read_format(data, format)
          descriptor = format_descriptor(format)
          medium = "\0".b * 24
          return [nil, nil] unless FFI::COM.vcall(data, 3, [P, P], I, descriptor, medium).zero?
          begin
            handle = medium[8, 8].unpack1("J")
            if format == 15
              paths = @window.send(:hdrop_paths, handle)
              return [Windows::ClipboardData.uri_list(paths), paths]
            end
            pointer = @kernel.fn(:GlobalLock, [P], P).call(handle)
            return [nil, nil] if pointer.null?
            size = @kernel.fn(:GlobalSize, [P], Fiddle::TYPE_SIZE_T).call(handle)
            return [nil, nil] if size > 16_777_216
            bytes = pointer[0, size].b
            type = @window.clipboard_type_name(format)
            bytes = case type
            when "text/plain" then bytes.unpack("v*").take_while(&:nonzero?).pack("v*").force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace)
            when "text/html" then Windows::ClipboardData.parse_html(bytes)
            when "image/png" then format == 17 ? Windows::ClipboardData.dibv5_to_png(bytes) : bytes
            when /^text\// then bytes.force_encoding("UTF-8").scrub
            else bytes
            end
            [bytes, nil]
          ensure
            @kernel.fn(:GlobalUnlock, [P], I).call(handle) if pointer && !pointer.null?
            @ole.fn(:ReleaseStgMedium, [P], Fiddle::TYPE_VOID).call(medium)
          end
        rescue ArgumentError
          [nil, nil]
        end

        def format_descriptor(format) = [format, 0, 1, -1, 1].pack("S< x6 Q< L< l< L< x4")

        def start(data)
          @window.send(:release_drag_capture)
          formats = data.content.formats.map { |type, bytes| @window.clipboard_payload(type, bytes) }
          formats = formats.to_h
          @source = Interface.new(self, :source, [
            [[I, U], ->(_this, escape, keys) { escape != 0 ? 0x40101 : (keys & 1).zero? ? 0x40100 : 0 }],
            [[], ->(*) { 0x40102 }]
          ])
          @data = Interface.new(self, :data, [
            [[P, P], ->(_this, descriptor, medium) { get_data(descriptor, medium, formats) }],
            [[P, P], ->(*) { E_NOTIMPL }],
            [[P], ->(_this, descriptor) { valid_source_format?(descriptor, formats) ? 0 : DV_E_FORMATETC }],
            [[P, P], ->(*) { E_NOTIMPL }],
            [[P, P, I], ->(*) { E_NOTIMPL }],
            [[U, P], ->(_this, direction, out) { enumerate(direction, out, formats) }],
            [[P, U, P, P], ->(*) { E_NOTIMPL }],
            [[U], ->(*) { E_NOTIMPL }],
            [[P], ->(*) { E_NOTIMPL }]
          ])
          selected = [0].pack("L<")
          status = @ole.fn(:DoDragDrop, [P, P, U, P], I).call(@data.pointer, @source.pointer,
            data.operations.reduce(0) { |bits, operation| bits | EFFECTS.fetch(operation) }, selected)
          result = status == 0x40100 ? EFFECTS.key(selected.unpack1("L<")) || :none : :none
          @window.finish_drag_source(result)
          result
        ensure
          @window.finish_drag_source(:none) if @window.drag_data
          @retired_interfaces ||= []
          [@source, @data].compact.each { |interface| FFI::COM.release(interface.pointer) }
          @retired_interfaces.concat([@source, @data, *Array(@enumerators)].compact)
          @retired_interfaces.reject! { |interface| interface.references <= 0 }
          @source = @data = nil
          @enumerators = nil
        end

        def get_data(descriptor, medium, formats = @source_formats)
          format = Fiddle::Pointer.new(descriptor)[0, 2].unpack1("S<")
          bytes = formats[format]
          return DV_E_FORMATETC unless bytes && valid_source_format?(descriptor, formats)
          memory = @window.clipboard_memory(bytes)
          Fiddle::Pointer.new(medium)[0, 24] = [1, memory.to_i, 0].pack("L< x4 Q< Q<")
          0
        end

        def valid_source_format?(descriptor, formats = @source_formats)
          format, _target, aspect, index, medium = Fiddle::Pointer.new(descriptor)[0, 32].unpack("S< x6 Q< L< l< L< x4")
          formats.key?(format) && aspect == 1 && index == -1 && (medium & 1) != 0
        end

        def enumerate(direction, out, formats = @source_formats)
          return E_NOTIMPL unless direction == 1
          formats = formats.keys
          index = 0
          enumerator = Interface.new(self, :enumerator, [
            [[U, P, P], ->(_this, count, destination, fetched) {
              selected = formats.drop(index).first(count)
              selected.each_with_index { |format, offset| Fiddle::Pointer.new(destination + offset * 32)[0, 32] = format_descriptor(format) }
              index += selected.length
              Fiddle::Pointer.new(fetched)[0, 4] = [selected.length].pack("L<") unless fetched.to_i.zero?
              selected.length == count ? 0 : S_FALSE
            }],
            [[U], ->(_this, count) { index = [index + count, formats.length].min; index < formats.length ? 0 : S_FALSE }],
            [[], ->(*) { index = 0; 0 }],
            [[P], ->(*) { E_NOTIMPL }]
          ])
          (@enumerators ||= []) << enumerator
          Fiddle::Pointer.new(out)[0, 8] = [enumerator.pointer].pack("J")
          0
        end
      end
    end
  end
end
