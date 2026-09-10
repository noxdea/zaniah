# frozen_string_literal: true

require "rbconfig"
require_relative "process_wire"

module Zaniah
  # Fixed parallelism, bounded data-only IPC, portable spawn or legacy fork.
  class ProcessPool
    def initialize(workers: 2, handler: nil, requires: [], load_paths: [], max_pending: workers * 2, max_bytes: 16 << 20, &block)
      raise ArgumentError, "workers must be in 1..32" unless workers.is_a?(Integer) && workers.between?(1, 32)
      raise ArgumentError, "max_pending must be in 1..1024" unless max_pending.is_a?(Integer) && max_pending.between?(1, 1024)
      raise ArgumentError, "max_bytes must be in 4096..67108864" unless max_bytes.is_a?(Integer) && max_bytes.between?(4096, 64 << 20)
      raise ArgumentError, "provide a named handler or a block, not both" if !!handler == !!block
      if handler
        raise ArgumentError, "handler must be a constant name" unless handler.is_a?(String) && handler.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
      elsif !Process.respond_to?(:fork)
        raise Error, "block workers require fork; use handler: and requires: on this platform"
      end
      @requires = checked_paths(requires, file: true)
      @load_paths = checked_paths(load_paths, file: false)
      @handler, @block, @max_pending, @max_bytes = handler&.dup&.freeze, block, max_pending, max_bytes
      @mutex, @condition, @queue, @pending, @control = Mutex.new, ConditionVariable.new, [], {}, Queue.new
      @workers = Array.new(workers) { Worker.new }
      @supervisor = Thread.new { supervise }
      @workers.each { |entry| entry.thread = Thread.new { run_worker(entry) } }
    end

    # Snapshot before enqueueing, so later caller mutations cannot race IPC.
    # Large snapshots should be submitted from a TaskExecutor background task.
    def submit(data)
      @mutex.synchronize { ensure_accepting_tasks }
      bytes = ProcessWire.encode_frame(data, @max_bytes)
      task = Task.new
      task.on_complete do
        @mutex.synchronize do
          @pending.delete(task)
          @queue.delete_if { |queued, _| queued.equal?(task) }
        end
        @control << task # Cancellation never waits on a pipe or child process.
      end
      @mutex.synchronize do
        ensure_accepting_tasks
        @pending[task] = true
        @queue << [task, bytes]
        @condition.signal
      end
      task
    end

    def shutdown(timeout: 2)
      raise ArgumentError, "timeout must be finite and positive" unless timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?
      tasks = @mutex.synchronize do
        @closed = true
        saved = @pending.keys
        @queue.clear
        @condition.broadcast
        saved
      end
      @control << :shutdown
      tasks.each { |task| complete_task(task, error: Task::Cancelled.new("process pool shut down")) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      [@supervisor, *@workers.map(&:thread)].each do |thread|
        next if thread.equal?(Thread.current)
        remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
        raise Task::Timeout, "process pool cleanup is still running" unless thread.join(remaining)
      end
      nil
    end

    private

    def checked_paths(paths, file:)
      raise ArgumentError, "worker paths must be an array" unless paths.is_a?(Array)
      paths.map do |path|
        raise ArgumentError, "worker paths must be absolute existing paths" unless path.is_a?(String) &&
          File.absolute_path(path) == path && (file ? File.file?(path) : File.directory?(path))
        path.dup.freeze
      end.freeze
    end

    def ensure_accepting_tasks
      raise Error, "process pool is shut down" if @closed
      raise Error, "process pool queue is full" if @pending.length >= @max_pending
    end

    def take_job(entry)
      @mutex.synchronize do
        @condition.wait(@mutex) while @queue.empty? && !@closed
        return if @closed
        task, bytes = @queue.shift
        entry.task = task
        [task, bytes]
      end
    end

    def run_worker(entry)
      while (job = take_job(entry))
        task, bytes = job
        value = error = nil
        begin
          unless task.done?
            start_worker(entry) unless entry.pid
            unless task.done? || @closed
              entry.writer.write(bytes)
              body = ProcessWire.read_payload(entry.reader, @max_bytes)
              raise Error, "process worker exited without a response" unless body
              response = ProcessWire.decode_payload(body)
              raise Error, "invalid process worker response" unless response.is_a?(Array) && response.length == 2 && [true, false].include?(response[0])
              unless response[0]
                raise Error, "invalid process worker error" unless response[1].is_a?(String)
                raise Error, response[1]
              end
              value = response[1]
            end
          end
        rescue StandardError => failure
          error = failure
        ensure
          retire = @mutex.synchronize do
            entry.task = nil
            @pending.delete(task)
            entry.retire || @closed || task.done? || error
          end
          stop_worker(entry) if retire
        end
        complete_task(task, value, error: error)
      end
    ensure
      stop_worker(entry)
    end

    def complete_task(task, value = nil, error: nil)
      task.resolve(value, error: error)
    rescue StandardError => failure
      begin
        warn "Process task callback failed: #{ProcessWire.error_message(failure)}"
      rescue StandardError
        nil
      end
    end

    def supervise
      loop do
        task = @control.pop
        @mutex.synchronize do
          @workers.each do |entry|
            next unless task == :shutdown || entry.task.equal?(task)
            next if entry.retire
            entry.retire = true
            terminate_worker_process(entry.pid) if entry.pid
          end
        end
        break if task == :shutdown
      end
    end

    def start_worker(entry)
      child_in, writer = IO.pipe
      reader, child_out = IO.pipe
      [reader, writer, child_in, child_out].each(&:binmode)
      writer.sync = true
      pid = if @handler
        jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? ["--yjit"] : []
        command = [RbConfig.ruby, *jit, *@load_paths.flat_map { |path| ["-I", path] },
          File.expand_path("process_wire.rb", __dir__), @handler, @max_bytes.to_s, *@requires]
        options = {in: child_in, out: child_out, err: STDERR, close_others: true}
        options[windows? ? :new_pgroup : :pgroup] = true
        Process.spawn({"RUBYOPT" => nil, "RUBYLIB" => nil}, *command, **options)
      else
        Process.fork do
          Process.setpgrp
          reader.close
          writer.close
          @workers.each { |other| [other.reader, other.writer].compact.each { |io| io.close unless io.closed? } }
          begin
            ProcessWire.serve(child_in, child_out, @max_bytes, @block)
            exit! 0
          rescue Exception
            exit! 1
          end
        end
      end
      @mutex.synchronize do
        entry.pid, entry.reader, entry.writer, entry.retire = pid, reader, writer, false
        terminate_worker_process(pid) if @closed || entry.task.done?
      end
    rescue Exception
      [reader, writer].compact.each { |io| io.close unless io.closed? }
      raise
    ensure
      [child_in, child_out].compact.each { |io| io.close unless io.closed? }
    end

    def windows? = /mswin|mingw/.match?(RbConfig::CONFIG.fetch("host_os"))

    def terminate_worker_process(pid)
      Process.kill("KILL", windows? ? pid : -pid)
    rescue Errno::EPERM => error
      # macOS can report EPERM for a group whose last process just exited.
      # Do not mask a real permission failure against a still-existing child.
      begin
        windows? ? Process.kill(0, pid) : Process.getpgid(pid)
      rescue Errno::ESRCH
        return
      end
      raise error
    rescue Errno::ESRCH
      begin
        Process.kill("KILL", pid) # A just-forked child may not have set its group yet.
      rescue Errno::ESRCH
        nil
      end
    end

    def stop_worker(entry)
      pid = @mutex.synchronize do
        saved, entry.pid = entry.pid, nil
        saved
      end
      return unless pid
      unless Process.waitpid(pid, Process::WNOHANG)
        terminate_worker_process(pid)
        Process.wait(pid)
      end
    rescue Errno::ECHILD
      nil
    rescue StandardError
      # Retain the exact child identity if the OS denies termination/reaping;
      # a later shutdown must not mistake a failed cleanup for no child.
      @mutex.synchronize { entry.pid = pid } if pid
      raise
    ensure
      [entry.reader, entry.writer].compact.each { |io| io.close unless io.closed? }
      entry.reader = entry.writer = nil
    end
  end
end

require_relative "process_pool/worker"
