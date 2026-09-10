# frozen_string_literal: true

module Zaniah
  module TextSystem
    class FontDB
      Face = Data.define(:path, :index, :family, :families, :weight, :width, :style, :fixed_pitch, :tables)
    end
  end
end
