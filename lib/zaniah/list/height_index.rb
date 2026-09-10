# frozen_string_literal: true

module Zaniah
  class List
    class HeightIndex
      attr_reader :count

      def initialize(count, estimate)
        raise ArgumentError, "count must be a nonnegative integer" unless count.is_a?(Integer) && count >= 0
        raise ArgumentError, "height must be finite and positive" unless estimate.is_a?(Numeric) && estimate.finite? && estimate.positive?
        @count, @estimate, @values = count, estimate.to_f, {}
        @tree = Array.new(count + 1) { |index| (index & -index) * @estimate }
      end

      def [](index)
        validate_index(index)
        @values.fetch(index, @estimate)
      end

      def update(index, height)
        validate_index(index)
        raise ArgumentError, "height must be finite and positive" unless height.is_a?(Numeric) && height.finite? && height.positive?
        delta = height.to_f - self[index]
        height == @estimate ? @values.delete(index) : @values[index] = height.to_f
        cursor = index + 1
        while cursor <= @count
          @tree[cursor] += delta
          cursor += cursor & -cursor
        end
        delta
      end

      def prefix(index)
        raise IndexError, "row boundary outside list" unless index.is_a?(Integer) && index.between?(0, @count)
        total = 0.0
        while index.positive?
          total += @tree[index]
          index -= index & -index
        end
        total
      end

      def total = prefix(@count)

      # Index containing y; count is the sentinel at/beyond the bottom edge.
      def index_at(y)
        raise ArgumentError, "row offset must be finite" unless y.is_a?(Numeric) && y.finite?
        return 0 if y <= 0
        index, accumulated = 0, 0.0
        bit = 1 << @count.bit_length
        while bit.positive?
          candidate = index + bit
          if candidate <= @count && accumulated + @tree[candidate] <= y
            index, accumulated = candidate, accumulated + @tree[candidate]
          end
          bit >>= 1
        end
        index
      end

      private

      def validate_index(index)
        raise IndexError, "row outside list" unless index.is_a?(Integer) && index.between?(0, @count - 1)
      end
    end
  end
end
