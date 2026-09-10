# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class ProcessPoolTest < Minitest::Test
  T = Zaniah
  HANDLER = File.expand_path("fixtures/process_handler.rb", __dir__)

  def pool(**options)
    @pool = T::ProcessPool.new(workers: 1, handler: "ProcessFixture", requires: [HANDLER], **options)
  end

  def teardown = @pool&.shutdown

  def test_spawned_handler_state_plain_data_snapshot_and_stdlib_require
    pool
    value = {"op" => "echo", "value" => ["日本", {"yes" => true, "n" => 1.5, "nil" => nil}]}
    original = value.fetch("value").dup
    task = @pool.submit(value)
    value["value"] = "changed"
    assert_equal original, task.await(timeout: 3)
    assert_equal 1, @pool.submit("op" => "state").await(timeout: 3)
    assert_equal 2, @pool.submit("op" => "state").await(timeout: 3)
    refute_equal Process.pid, @pool.submit("op" => "pid").await(timeout: 3)
    assert_equal !!(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?), @pool.submit("op" => "jit").await(timeout: 3)
    assert @pool.submit("op" => "frozen", "value" => ["frozen"]).await(timeout: 3)
    assert_empty @pool.submit("op" => "prism", "text" => "1 + 2").await(timeout: 3)
    assert_predicate task.await, :frozen?
  end

  def test_two_actual_children_handle_work_concurrently
    @pool = T::ProcessPool.new(workers: 2, handler: "ProcessFixture", requires: [HANDLER])
    tasks = 2.times.map { @pool.submit("op" => "sleep", "seconds" => 0.1) }
    pids = tasks.map { |task| task.await(timeout: 3) }
    assert_equal 2, pids.uniq.length
    refute_includes pids, Process.pid
    @pool.shutdown
    pids.each { |pid| assert_raises(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) } }
  end

  def test_handler_stdout_cannot_corrupt_private_protocol_output
    _, diagnostic = capture_subprocess_io do
      pool
      assert_equal "ok", @pool.submit("op" => "stdout").await(timeout: 3)
      @pool.shutdown
    end
    assert_match(/handler chatter/, diagnostic)
    assert_match(/constant chatter/, diagnostic)
  end

  def test_handler_can_require_framework_without_reentering_worker_bootstrap
    @pool = T::ProcessPool.new(workers: 1, handler: "RecursiveProcessFixture",
      requires: [File.expand_path("fixtures/process_recursive_handler.rb", __dir__)],
      load_paths: [File.expand_path("../lib", __dir__)])
    assert_equal ["日本", 1], @pool.submit("日本").await(timeout: 3)
    assert_equal [42, 1], @pool.submit(42).await(timeout: 3)
    @pool.shutdown
  end

  def test_cancel_hung_work_is_nonblocking_and_replaces_reaped_child
    pool
    pid = @pool.submit("op" => "pid").await(timeout: 3)
    task = @pool.submit("op" => "hang")
    wait_until { @pool.instance_variable_get(:@workers).first.task.equal?(task) }
    started = monotonic
    task.cancel
    assert_operator monotonic - started, :<, 0.2
    assert_raises(T::Task::Cancelled) { task.await }
    replacement = @pool.submit("op" => "pid").await(timeout: 3)
    refute_equal pid, replacement
    assert_raises(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
  end

  def test_queue_limit_and_cancel_queued_job_without_running_it
    pool(max_pending: 2)
    blocked = @pool.submit("op" => "hang")
    queued = @pool.submit("op" => "state")
    assert_raises(T::Error) { @pool.submit("op" => "state") }
    queued.cancel
    replacement = @pool.submit("op" => "state")
    blocked.cancel
    assert_equal 1, replacement.await(timeout: 3)
    assert_raises(T::Task::Cancelled) { queued.await }
  end

  def test_shutdown_terminates_running_work_and_cancels_queue
    pool(max_pending: 3)
    pid = @pool.submit("op" => "pid").await(timeout: 3)
    tasks = [@pool.submit("op" => "hang"), @pool.submit("op" => "state")]
    wait_until { @pool.instance_variable_get(:@workers).first.task.equal?(tasks.first) }
    started = monotonic
    @pool.shutdown
    assert_operator monotonic - started, :<, 1
    tasks.each { |task| assert_raises(T::Task::Cancelled) { task.await } }
    assert_raises(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
    assert_raises(T::Error) { @pool.submit(nil) }
    @pool.shutdown
  end

  def test_shutdown_interrupts_blocked_large_pipe_write_during_worker_loading
    loader = File.expand_path("fixtures/process_blocked_loader.rb", __dir__)
    @pool = T::ProcessPool.new(workers: 1, handler: "ProcessFixture", requires: [loader])
    task = @pool.submit("op" => "echo", "value" => "x" * (2 << 20))
    wait_until { @pool.instance_variable_get(:@workers).first.pid }
    pid = @pool.instance_variable_get(:@workers).first.pid
    started = monotonic
    @pool.shutdown
    assert_operator monotonic - started, :<, 1
    assert_raises(T::Task::Cancelled) { task.await }
    assert_raises(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
  end

  def test_real_signal_failure_does_not_forget_child_identity
    pool
    pid = @pool.submit("op" => "pid").await(timeout: 3)
    entry = @pool.instance_variable_get(:@workers).first
    @pool.stub(:terminate_worker_process, ->(_) { raise Errno::EPERM }) do
      assert_raises(Errno::EPERM) { @pool.send(:stop_worker, entry) }
    end
    assert_equal pid, entry.pid
    @pool.shutdown
    assert_raises(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
  end

  def test_invalid_input_result_error_and_crash_are_reported_and_pool_recovers
    pool(max_bytes: 4096)
    [Object.new, :symbol, {key: "value"}, Float::NAN, "\xff".b, "x" * 4097].each do |value|
      assert_raises(ArgumentError) { @pool.submit(value) }
    end
    cyclic = []; cyclic << cyclic
    assert_raises(ArgumentError) { @pool.submit(cyclic) }
    {"error" => /ArgumentError: fixture failure/, "object" => /plain JSON/,
      "huge" => /exceeds 4096/, "crash" => /exited without a response/}.each do |operation, message|
      error = assert_raises(T::Error) { @pool.submit("op" => operation, "bytes" => 4097).await(timeout: 3) }
      assert_match message, error.message
      assert_equal 7, @pool.submit("op" => "echo", "value" => 7).await(timeout: 3)
    end
  end

  def test_missing_handler_is_reported_without_hanging
    @pool = T::ProcessPool.new(workers: 1, handler: "NoSuchHandler", requires: [HANDLER])
    error = assert_raises(T::Error) { @pool.submit(nil).await(timeout: 3) }
    assert_match(/NameError/, error.message)
  end

  def test_callback_error_does_not_kill_worker_thread
    pool
    task = @pool.submit("op" => "sleep", "seconds" => 0.01)
    task.on_complete { raise "callback broke" }
    _, diagnostic = capture_io do
      task.await(timeout: 3)
      assert_equal 8, @pool.submit("op" => "echo", "value" => 8).await(timeout: 3)
    end
    assert_match(/callback broke/, diagnostic)
  end

  def test_fork_block_compatibility_uses_same_bounded_data_contract
    skip "fork unavailable" unless Process.respond_to?(:fork)
    @pool = T::ProcessPool.new(workers: 1) { |value| value * 2 }
    assert_equal 42, @pool.submit(21).await(timeout: 3)
    assert_raises(ArgumentError) { @pool.submit(Object.new) }
  end

  def test_framing_rejects_oversize_truncation_invalid_utf8_and_nesting
    ["x", [100_000].pack("N"), [4].pack("N") + "{}", [1].pack("N") + "\xff".b].each do |bytes|
      assert_raises(IOError) { T::ProcessWire.read_payload(StringIO.new(bytes), 4096) }
    end
    assert_nil T::ProcessWire.read_payload(StringIO.new(""), 4096)
    assert_raises(JSON::ParserError) { T::ProcessWire.decode_payload("[") }
    assert_raises(JSON::NestingError) { T::ProcessWire.decode_payload("[" * 100 + "0" + "]" * 100) }
    value = {"json_class" => "Object", "data" => nil}
    assert_equal value, T::ProcessWire.decode_payload(JSON.generate(value))
  end

  def test_byte_preflight_rejects_large_strings_and_escaped_aggregate_before_json_generation
    pool(max_bytes: 4096)
    JSON.stub(:generate, ->(*) { flunk "oversized input reached JSON generation" }) do
      ["x" * 4096, ["x" * 3000, "y" * 3000], "\x00" * 1000, "\\" * 3000].each do |value|
        assert_raises(ArgumentError) { @pool.submit(value) }
      end
    end
    ["\"\\\b\t\n\f\r\x00日本", [1, 2.5, true, false, nil], {"a" => "\n"}].each do |value|
      assert_equal JSON.generate(value).bytesize + 4, T::ProcessWire.encode_frame(value, 4096).bytesize
    end
  end

  def test_rejects_invalid_configuration
    [{workers: 0}, {workers: 33}, {max_pending: 0}, {max_bytes: 1}, {handler: "system('bad')"},
      {requires: ["relative.rb"]}, {load_paths: ["."]}].each do |options|
      assert_raises(ArgumentError) { T::ProcessPool.new(handler: "ProcessFixture", requires: [HANDLER], **options) }
    end
    assert_raises(ArgumentError) { T::ProcessPool.new }
    assert_raises(ArgumentError) { T::ProcessPool.new(handler: "ProcessFixture") { 1 } }
  end

  private

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  def wait_until
    deadline = monotonic + 3
    until yield
      raise "worker did not start" if monotonic > deadline
      sleep 0.001
    end
  end
end
