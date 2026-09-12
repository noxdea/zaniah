# frozen_string_literal: true

require_relative "devtools/inspector"
require_relative "devtools/stats_overlay"
require_relative "devtools/hot_reload"

module Zaniah
  module DevTools
    module_function

    def attach(window, **options) = Inspector.new(window, **options)
  end
end
