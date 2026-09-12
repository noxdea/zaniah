# frozen_string_literal: true

require_relative "subscription"
require_relative "entity"
require_relative "entity_context"
require_relative "task_executor"

module Zaniah
  class App
    attr_reader :windows, :executor

    def initialize(clock: MONOTONIC_CLOCK)
      @slots, @generations, @free, @windows, @globals = [], [], [], [], {theme: Theme.dark}
      @listeners, @effects, @updating, @flushing = {}, [], 0, false
      @clock = clock
      @executor = TaskExecutor.new(clock: clock)
    end

    def new_entity
      id = @free.pop || @slots.length
      @generations[id] ||= 0
      entity = Entity.new(id, @generations[id])
      @slots[id] = yield(EntityContext.new(self, entity))
      entity
    rescue Exception
      @slots[id] = nil if id
      @free << id if id && !@free.include?(id)
      raise
    end

    def read(entity)
      validate(entity)
      @slots[entity.id]
    end

    def update(entity)
      validate(entity)
      @updating += 1
      begin
        yield(@slots[entity.id], EntityContext.new(self, entity))
      ensure
        @updating -= 1
        flush_effects if @updating.zero?
      end
    end

    def release(entity)
      validate(entity)
      object = @slots[entity.id]
      @slots[entity.id] = nil
      @generations[entity.id] += 1
      @free << entity.id
      @listeners.delete_if { |(target, _), _| target == entity }
      @listeners.each_value { |listeners| listeners.delete_if { |owner, _| owner == entity } }
      object.dispose if object.respond_to?(:dispose)
    end

    def entity_count = @slots.length - @free.length

    def global(key, value = (missing = true))
      missing ? @globals.fetch(key) : @globals[key] = value
    end

    def listen(kind, target, owner: nil, &callback)
      validate(target)
      entry = [owner, callback]
      list = (@listeners[[target, kind]] ||= [])
      list << entry
      Subscription.new { list.delete(entry) }
    end

    def enqueue(kind, entity, event = nil)
      @effects << [kind, entity, event]
      flush_effects if @updating.zero? && !@flushing
    end

    def flush_effects
      return if @flushing
      @flushing = true
      dirty = false
      until @effects.empty?
        effects, @effects = @effects, []
        notified = {}
        effects.each do |kind, entity, event|
          next unless alive?(entity)
          next if kind == :notify && notified[entity]
          notified[entity] = true if kind == :notify
          dirty ||= kind == :notify
          (@listeners[[entity, kind]] || []).dup.each do |owner, callback|
            next if owner && !alive?(owner)
            if owner
              args = [read(owner), read(entity)]
              args << event if kind == :emit
              callback.call(*args, EntityContext.new(self, owner))
            else
              callback.call(read(entity), event)
            end
          end
        end
      end
      @windows.each(&:request_frame) if dirty
    ensure
      @flushing = false
    end

    def open_window(**options, &render)
      options[:clock] ||= @clock
      window = Platform.open_window(**options)
      window.app = self
      @windows << window
      @globals[:theme] = platform_theme(window)
      window.on_appearance do |appearance|
        @globals[:theme] = platform_theme(window, appearance)
        @windows.each(&:request_frame)
      end
      window.draw(&render) if render
      window
    end

    def run
      until @windows.empty? || @windows.all?(&:closed?)
        @hot_reloads&.each(&:poll)
        @executor.drain
        @windows.reject(&:closed?).each(&:tick)
        @executor.wait(0.05) unless @windows.any? { |window| window.dirty? || window.animation_active? }
      end
    ensure
      @hot_reloads&.each(&:close)
      @executor.shutdown
    end

    def hot_reload(paths, **options, &block)
      require_relative "devtools"
      reload = DevTools::HotReload.new(self, paths, **options, &block)
      (@hot_reloads ||= []) << reload
      reload
    end

    def alive?(entity) = @generations[entity.id] == entity.generation && !@free.include?(entity.id) && entity.id < @slots.length

    private

    def platform_theme(window, appearance = window.appearance)
      theme = Theme.for(appearance)
      window.reduced_motion? ? theme.with(motion: theme.motion.with(reduced: true)) : theme
    end

    def validate(entity)
      raise Error, "entity has been released" unless alive?(entity)
    end
  end
end
