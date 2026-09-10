# frozen_string_literal: true

require_relative "library"

module Zaniah
  module FFI
    module COM
      extend self
      def vcall(this, index, types, result, *values)
        raise ArgumentError, "null COM interface" if this.to_i.zero?
        table = Fiddle::Pointer.new(this.to_i)[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
        address = Fiddle::Pointer.new(table)[index * Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_VOIDP].unpack1("J")
        @functions ||= {}
        function = @functions[[address, types, result]] ||= Fiddle::Function.new(address, [Fiddle::TYPE_VOIDP, *types], result)
        function.call(this, *values)
      end
      def release(this) = vcall(this, 2, [], Fiddle::TYPE_INT)
      def check(status)
        raise Zaniah::Error, "COM failure 0x#{(status & 0xffffffff).to_s(16)}" unless (status & 0x80000000).zero?
        status
      end
    end
  end
end
