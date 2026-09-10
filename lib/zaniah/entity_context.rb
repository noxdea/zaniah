# frozen_string_literal: true

module Zaniah
  class EntityContext
    attr_reader :app, :entity

    def initialize(app, entity) = (@app, @entity = app, entity)
    def notify = app.enqueue(:notify, entity)
    def emit(event) = app.enqueue(:emit, entity, event)
    def observe(target, &callback) = app.listen(:notify, target, owner: entity, &callback)
    def subscribe(target, &callback) = app.listen(:emit, target, owner: entity, &callback)
    def spawn(&block) = app.executor.spawn { block.call(self) }
    def background(&block) = app.executor.background(&block).await
    def update(&block) = app.executor.post { block.call(app) }
    def theme = app.global(:theme)
  end
end
