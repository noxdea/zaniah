# frozen_string_literal: true

require_relative "zaniah/version"
require_relative "zaniah/data_compat"
require_relative "zaniah/error"
require_relative "zaniah/configuration"

module Zaniah
  def self.configuration
    @configuration ||= Configuration.new(font_raster: :native, shaper: :native,
                                        font_db: :native, segmenter: :native)
  end
  def self.configure = yield(configuration)
end

require_relative "zaniah/geometry"
require_relative "zaniah/unicode"
require_relative "zaniah/scene"
require_relative "zaniah/png"
require_relative "zaniah/gpu"
require_relative "zaniah/layout"
require_relative "zaniah/app"
require_relative "zaniah/process_pool"
require_relative "zaniah/input"
require_relative "zaniah/element"
Zaniah.autoload(:SVG, File.expand_path("zaniah/svg", __dir__))
require_relative "zaniah/list"
require_relative "zaniah/platform"
require_relative "zaniah/text_system"
