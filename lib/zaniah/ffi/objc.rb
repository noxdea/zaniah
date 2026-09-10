# frozen_string_literal: true

require_relative "struct"

module Zaniah
  module FFI
    module ObjC
      extend self
      P = Fiddle::TYPE_VOIDP
      LIB = Library.new("/usr/lib/libobjc.A.dylib")
      MESSAGE_SEND = LIB.handle["objc_msgSend"]
      SCALARS = {void: Fiddle::TYPE_VOID, pointer: P, int: Fiddle::TYPE_INT, uint: Fiddle::TYPE_UINT,
        long: Fiddle::TYPE_INT64_T, ulong: Fiddle::TYPE_UINT64_T, double: Fiddle::TYPE_DOUBLE,
        float: Fiddle::TYPE_FLOAT, bool: Fiddle::TYPE_UCHAR}.freeze
      NO_ARGUMENTS = [].freeze
      @selectors, @signatures, @closures, @classes = {}, {}, [], {}
      @signature_lookup = [nil, nil]

      def klass(name)
        @classes[name] || begin
          value = LIB.fn(:objc_getClass, [P], P).call(name).to_i
          @classes[name] = value unless value.zero?
          value
        end
      end
      def selector(name) = @selectors[name] ||= LIB.fn(:sel_registerName, [P], P).call(name.to_s).to_i
      def send(receiver, name, *values, args: NO_ARGUMENTS, result: :pointer)
        raise ArgumentError, "wrong number of native arguments" unless values.length == args.length
        @signature_lookup[0], @signature_lookup[1] = args, result
        signature = @signatures[@signature_lookup]
        unless signature
          # Fiddle already implements scalar calling conventions. Only aggregate
          # arguments/returns need the lower-level libffi packing path.
          signature = if SCALARS.key?(result) && args.all? { |type| SCALARS.key?(type) }
            Fiddle::Function.new(MESSAGE_SEND, [P, P, *args.map { |type| SCALARS.fetch(type) }],
              result == :pointer ? Fiddle::TYPE_UINTPTR_T : SCALARS.fetch(result), need_gvl: true)
          else
            Struct::Signature.new([:pointer, :pointer, *args], result)
          end
          @signatures[[args.dup.freeze, result].freeze] = signature
        end
        return signature.call(receiver, selector(name), *values) if signature.is_a?(Fiddle::Function)
        address = MESSAGE_SEND
        if RUBY_PLATFORM.include?("x86_64") && [:rect, :region, :clear_color].include?(result)
          address = LIB.handle["objc_msgSend_stret"]
        end
        signature.call(address, receiver, selector(name), *values)
      end
      def string(value)
        bytes = value.to_s.encode(Encoding::UTF_8)
        send(klass("NSString"), "stringWithUTF8String:", Fiddle::Pointer[bytes + "\0"], args: [:pointer])
      end
      def text(object)
        return "" if object.to_i.zero?
        pointer = send(object, "UTF8String")
        pointer.zero? ? "" : Fiddle::Pointer.new(pointer).to_s.force_encoding(Encoding::UTF_8)
      end
      def alloc(name) = send(klass(name), "alloc")
      def new(name) = send(alloc(name), "init")
      def release(object)
        send(object, "release", result: :void) unless object.to_i.zero?
      end

      def subclass(name, parent, protocols: [])
        found = klass(name)
        return found unless found.zero?
        klass = LIB.fn(:objc_allocateClassPair, [P, P, Fiddle::TYPE_SIZE_T], P).call(self.klass(parent), name, 0).to_i
        protocols.each do |protocol|
          ptr = LIB.fn(:objc_getProtocol, [P], P).call(protocol)
          LIB.fn(:class_addProtocol, [P, P], Fiddle::TYPE_BOOL).call(klass, ptr) unless ptr.null?
        end
        yield klass
        LIB.fn(:objc_registerClassPair, [P], Fiddle::TYPE_VOID).call(klass)
        klass
      end

      def method(klass, name, args: [], result: :void, encoding:, &block)
        signature = Struct::Signature.new([:pointer, :pointer, *args], result)
        closure = signature.closure(&block)
        @closures << signature
        ok = LIB.fn(:class_addMethod, [P, P, P, P], Fiddle::TYPE_BOOL).call(klass, selector(name), closure, encoding)
        raise LoadError, "cannot install #{name}" unless ok
      end
    end
  end
end
