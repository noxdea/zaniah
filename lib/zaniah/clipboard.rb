# frozen_string_literal: true

module Zaniah
  module Clipboard
    class Item
      attr_reader :types, :formats

      def initialize(formats)
        raise TypeError, "clipboard formats must be a Hash" unless formats.is_a?(Hash)

        @formats = formats.each_with_object({}) do |(type, value), result|
          unless type.is_a?(String) && type.match?(/\A[^\s\/]+\/[^\s\/]+\z/)
            raise ArgumentError, "invalid clipboard MIME type #{type.inspect}"
          end
          raise TypeError, "clipboard data must be a String" unless value.is_a?(String)

          data = value.dup
          if type.start_with?("text/")
            data = data.encoding == Encoding::BINARY ? data.force_encoding(Encoding::UTF_8) : data.encode(Encoding::UTF_8)
            raise Encoding::InvalidByteSequenceError, "invalid UTF-8 clipboard text" unless data.valid_encoding?
          else
            data.force_encoding(Encoding::BINARY)
          end
          result[type.dup.freeze] = data.freeze
        end.freeze
        @types = @formats.keys.freeze
        freeze
      end

      def fetch(type) = @formats.fetch(type)

      def ==(other) = other.instance_of?(self.class) && @formats == other.formats
      alias eql? ==
      def hash = [self.class, @formats].hash
    end

    class Content < Item
    end
  end
end
