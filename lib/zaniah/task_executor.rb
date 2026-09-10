# frozen_string_literal: true

require "thread"
require_relative "task"

module Zaniah
  class TaskExecutor
    def self.current = Thread.current[:zaniah_executor]

    def initialize(workers: 2)
      @jobs, @foreground = Queue.new, Queue.new
      @wake, @condition = Mutex.new, ConditionVariable.new
      @timers = []
      @threads = Array.new(workers) do
        Thread.new do
          while (job = @jobs.pop)
            task, work = job
            next if task.done?
            begin
              task.resolve(work.call)
            rescue StandardError => error
              task.resolve(error: error)
            end
          end
        end
      end
    end

    def background(&block)
      raise Error, "executor is shut down" if @closed
      task = Task.new
      @jobs << [task, block]
      task
    end

    def spawn(&block)
      raise Error, "executor is shut down" if @closed
      task = Task.new
      fiber = Fiber.new do
        Thread.current[:zaniah_executor] = self
        Thread.current[:zaniah_task] = task
        begin
          task.resolve(block.call)
        rescue StandardError => error
          task.resolve(error: error)
        end
      end
      post { fiber.resume unless task.done? }
      task
    end

    def await(task, timeout: nil)
      raise Error, "await must run in an executor fiber" unless self.class.current.equal?(self)
      return task.await(timeout: timeout) if task.done?
      fiber, owner = Fiber.current, Thread.current[:zaniah_task]
      finished, error, deadline = false, nil, nil
      finish = lambda do |failure = nil|
        next if finished
        finished, error = true, failure
        fiber.resume if fiber.alive? && !owner.done?
      end
      subscription = task.on_complete { post { finish.call } }
      cancellation = owner.on_complete { post { subscription.detach; @timers.delete(deadline) if deadline } }
      if timeout
        raise ArgumentError, "timeout must be nonnegative" unless timeout.is_a?(Numeric) && timeout >= 0
        deadline = [Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout, -> { finish.call(Task::Timeout.new("task timed out")) }]
        @timers << deadline
      end
      Fiber.yield
      raise error if error
      task.await(timeout: 0)
    ensure
      subscription&.detach
      cancellation&.detach
      @timers.delete(deadline) if deadline
    end

    def post(&block)
      @foreground << block
      @wake.synchronize { @condition.signal }
    end

    def drain
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      due, @timers = @timers.partition { |deadline, _| deadline <= now }
      due.each { |_, callback| callback.call }
      loop { @foreground.pop(true).call }
    rescue ThreadError
      nil
    end

    def wait(seconds)
      deadline = @timers.map(&:first).min
      seconds = [seconds, [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max].min if deadline
      @wake.synchronize { @condition.wait(@wake, seconds) if @foreground.empty? }
    end

    def shutdown
      return if @closed
      @closed = true
      @threads.length.times { @jobs << nil }
      @threads.each(&:join)
    end
  end
end
