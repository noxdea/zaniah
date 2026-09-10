# frozen_string_literal: true

module Zaniah
  Configuration = Struct.new(:font_raster, :shaper, :font_db, :segmenter, keyword_init: true)
end
