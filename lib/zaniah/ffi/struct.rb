# frozen_string_literal: true

require_relative "library"

module Zaniah
  module FFI
    # Fiddle's public Function API has scalar types only. libffi itself handles
    # aggregate arguments/returns, including arm64 homogeneous float aggregates.
    module Struct
      extend self
      P = Fiddle::TYPE_VOIDP
      I = Fiddle::TYPE_INT
      V = Fiddle::TYPE_VOID
      LIB = Library.new("/usr/lib/libffi.dylib", "libffi.so.8", "libffi.so.7", "libffi-8.dll")
      ABI = if RUBY_PLATFORM.include?("aarch64") || RUBY_PLATFORM.include?("arm64") then 1
      elsif RUBY_PLATFORM.match?(/mingw|mswin/) then 2
      else 2
      end
      TYPES = {void: ["void", nil], pointer: ["pointer", "J"], int: ["sint32", "i!"],
               uint: ["uint32", "I!"], long: ["sint64", "q"], ulong: ["uint64", "Q"],
               double: ["double", "d"], float: ["float", "f"], bool: ["uint8", "C"]}.freeze
      AGGREGATES = {point: [:double, :double], size: [:double, :double],
                    rect: [:double, :double, :double, :double], range: [:ulong, :ulong],
                    region: [:ulong] * 6, scissor: [:ulong] * 4, clear_color: [:double] * 4}.freeze

      def type(name)
        @types ||= {}
        @types[name] ||= if TYPES.key?(name)
          Fiddle::Pointer.new(LIB.handle["ffi_type_#{TYPES.fetch(name)[0]}"])
        else
          elements = (AGGREGATES.fetch(name).map { |t| type(t).to_i } << 0).pack("J*")
          pointer = Fiddle::Pointer.malloc(24, Fiddle::RUBY_FREE)
          pointer[0, 24] = [0, 0, 13, Fiddle::Pointer[elements].to_i].pack("JSSx4J")
          (@keep ||= []) << elements
          pointer
        end
      end

      def pack(name, value)
        return value.pack(AGGREGATES.fetch(name).map { |t| TYPES.fetch(t)[1] }.join) if AGGREGATES.key?(name)
        format = TYPES.fetch(name)[1]
        return "" unless format
        [name == :pointer ? (value.respond_to?(:to_ptr) ? value.to_ptr.to_i : value.to_i) : value].pack(format)
      end

      def unpack(name, pointer)
        return nil if name == :void
        if AGGREGATES.key?(name)
          format = AGGREGATES.fetch(name).map { |t| TYPES.fetch(t)[1] }.join
          pointer[0, pack(name, Array.new(AGGREGATES[name].length, 0)).bytesize].unpack(format)
        else
          format = TYPES.fetch(name)[1]
          pointer[0, [0].pack(format).bytesize].unpack1(format)
        end
      end

    end
  end
end

require_relative "struct/signature"
