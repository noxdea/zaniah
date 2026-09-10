# frozen_string_literal: true

module Zaniah
  module Platform
    FileEvent = Data.define(:kind, :path, :old_path) unless const_defined?(:FileEvent)
  end
end
