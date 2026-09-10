# frozen_string_literal: true

module Zaniah
  Entity = Data.define(:id, :generation) do
    def read(app) = app.read(self)
    def update(app, &block) = app.update(self, &block)
    def release(app) = app.release(self)
  end
end
