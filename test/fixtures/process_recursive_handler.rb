# frozen_string_literal: true

require "zaniah"

module RecursiveProcessFixture
  def self.call(data)
    [data, $LOADED_FEATURES.count { |path| path.end_with?("/zaniah/process_wire.rb") }]
  end
end
