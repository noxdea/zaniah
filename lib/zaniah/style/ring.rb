# frozen_string_literal: true

module Zaniah
  Ring = Data.define(:width, :color, :offset) do
    class << self
      alias record_new new

      def new(width, color = nil, offset = 0)
        record_new(width.to_f, color && Color.parse(color), offset.to_f)
      end
    end
  end
end
