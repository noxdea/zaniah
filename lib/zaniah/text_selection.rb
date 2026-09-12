# frozen_string_literal: true

module Zaniah
  TextSelection = Data.define(:anchor, :head) do
    class << self
      alias record_new new

      def new(anchor, head = anchor)
        raise ArgumentError, "selection offsets must be nonnegative integers" unless [anchor, head].all? { |value| value.is_a?(Integer) && value >= 0 }
        record_new(anchor, head)
      end
    end

    def range = [anchor, head].min...[anchor, head].max
    def collapsed? = anchor == head
    def normalized = TextSelection.new(range.begin, range.end)
  end
end
