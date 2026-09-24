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

  class DragData
    OPERATIONS = %i[copy move link].freeze
    attr_reader :items, :image, :operations, :on_move

    def initialize(items:, image: nil, operations: [:copy], on_move: nil)
      raise TypeError, "drag items must be an Array of Clipboard::Item" unless items.is_a?(Array) && !items.empty? && items.all? { |item| item.is_a?(Clipboard::Item) }
      raise ArgumentError, "invalid drag operations" unless operations.is_a?(Array) && !operations.empty? && operations.all? { |operation| OPERATIONS.include?(operation) }
      raise ArgumentError, "move operations require an on_move callback" if operations.include?(:move) && !on_move.respond_to?(:call)
      @items, @image, @operations, @on_move = items.dup.freeze, image, operations.uniq.freeze, on_move
      freeze
    end

    def types = @items.flat_map(&:types).uniq.freeze
    def content(types: self.types)
      raise TypeError, "drag types must be an Array" unless types.is_a?(Array)
      formats = types.each_with_object({}) do |type, result|
        item = @items.find { |entry| entry.types.include?(type) }
        result[type] = item.fetch(type) if item
      end
      Clipboard::Content.new(formats)
    end
  end
end
