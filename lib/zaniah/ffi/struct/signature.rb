# frozen_string_literal: true

module Zaniah
  module FFI
    module Struct
      class Signature
        def initialize(arguments, result)
          @arguments, @result = arguments, result
          @types = arguments.map { |type| Struct.type(type).to_i }.pack("J*")
          @cif = Fiddle::Pointer.malloc(256, Fiddle::RUBY_FREE)
          status = LIB.fn(:ffi_prep_cif, [P, I, I, P, P], I).call(@cif, ABI, arguments.length, Struct.type(result), @types)
          raise LoadError, "libffi rejected signature (#{status})" unless status.zero?
        end

        def call(address, *arguments)
          raise ArgumentError, "wrong number of native arguments" unless arguments.length == @arguments.length
          values = @arguments.zip(arguments).map { |type, value| Struct.pack(type, value) }
          pointers = values.map { |value| Fiddle::Pointer[value].to_i }.pack("J*")
          result = Fiddle::Pointer.malloc(64, Fiddle::RUBY_FREE)
          LIB.fn(:ffi_call, [P, P, P, P], V).call(@cif, address, result, pointers)
          Struct.unpack(@result, result)
        end

        def closure(&block)
          location = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
          memory = LIB.fn(:ffi_closure_alloc, [Fiddle::TYPE_SIZE_T, P], P).call(256, location)
          raise NoMemoryError, "ffi_closure_alloc" if memory.null?
          callback = Fiddle::Closure::BlockCaller.new(V, [P, P, P, P]) do |_cif, result, args, _user|
            arguments = @arguments.each_with_index.map do |type, index|
              address = Fiddle::Pointer.new(args)[index * Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_VOIDP].unpack1("J")
              Struct.unpack(type, Fiddle::Pointer.new(address))
            end
            bytes = Struct.pack(@result, block.call(*arguments))
            Fiddle::Pointer.new(result)[0, bytes.bytesize] = bytes unless bytes.empty?
          end
          code = location[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
          status = LIB.fn(:ffi_prep_closure_loc, [P, P, P, P, P], I).call(memory, @cif, callback, 0, code)
          raise LoadError, "libffi rejected closure (#{status})" unless status.zero?
          # Objective-C classes outlive Ruby wrappers: retain their IMPs for process lifetime.
          (@closures ||= []) << [memory, callback]
          code
        end
      end
    end
  end
end
