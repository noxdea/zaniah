# frozen_string_literal: true

require "thread"
require_relative "subscription"

module Zaniah
  class Task
    def initialize
      @mutex, @condition = Mutex.new, ConditionVariable.new
      @done = false
      @callbacks = []
    end

    def resolve(value = nil, error: nil)
      callbacks = @mutex.synchronize do
        return if @done
        @value, @error, @done = value, error, true
        @condition.broadcast
        saved, @callbacks = @callbacks, []
        saved
      end
      callbacks.each(&:call)
    end

    def await(timeout: nil)
      return TaskExecutor.current.await(self, timeout: timeout) if TaskExecutor.current && !done?
      deadline = timeout && Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      @mutex.synchronize do
        until @done
          remaining = deadline && deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Timeout, "task timed out" if remaining && remaining <= 0
          @condition.wait(@mutex, remaining)
        end
        raise @error if @error
        @value
      end
    end

    def cancel = resolve(error: Cancelled.new("task cancelled"))
    def done? = @mutex.synchronize { @done }

    def on_complete(&callback)
      complete = @mutex.synchronize { @done || (@callbacks << callback; false) }
      callback.call if complete
      Subscription.new { @mutex.synchronize { @callbacks.delete(callback) } }
    end
  end
end

require_relative "task/cancelled"
require_relative "task/timeout"
