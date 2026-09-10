# frozen_string_literal: true

module Zaniah
  class Canvas < Element
    def initialize(&paint)
      super()
      @painter = paint
    end

    def paint(bounds, state, prepaint, cx)
      super
      @painter.call(bounds, cx)
    end
  end
end
