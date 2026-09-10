# frozen_string_literal: true
require_relative "test_helper"

class TaskExecutorAwaitTest < Minitest::Test
  def setup = @executor = Zaniah::TaskExecutor.new(workers: 1)
  def teardown = @executor.shutdown
  def test_foreground_await_yields_and_resumes_on_foreground
    pending = Zaniah::Task.new
    thread = Thread.current
    events = []
    task = @executor.spawn do
      events << :waiting
      value = pending.await
      assert_same thread, Thread.current
      events << value
    end
    @executor.drain
    assert_equal [:waiting], events
    @executor.post { events << :responsive }
    @executor.drain
    Thread.new { pending.resolve(42) }.join
    @executor.drain
    assert_equal [:waiting, :responsive, 42], events
    assert task.done?
  end
  def test_timeout_does_not_cancel_shared_work_and_cancel_does_not_resume
    pending = Zaniah::Task.new
    task = @executor.spawn { pending.await(timeout: 0) }
    @executor.drain
    @executor.drain
    assert_raises(Zaniah::Error) { task.await }
    refute pending.done?
    ran = false
    cancelled = @executor.spawn { pending.await; ran = true }
    @executor.drain
    cancelled.cancel
    pending.resolve
    @executor.drain
    refute ran
  end
end
