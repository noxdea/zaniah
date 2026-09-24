# frozen_string_literal: true

require "zaniah"
require "zaniah/platform/linux"

png = "\x89PNG".b + "x".b * 1_100_000
to_child, commands = IO.pipe
responses, from_child = IO.pipe
child = fork do
  commands.close
  responses.close
  to_child.sync = from_child.sync = true
  window = nil
  begin
    window = Zaniah::Platform::Linux::Window.new(width: 64, height: 64)
    raise "parent did not start transfer" unless to_child.gets == "read\n"
    content = window.read_clipboard(types: %w[image/png text/html text/plain])
    raise "X11 typed clipboard read failed" unless content.types == %w[image/png text/html text/plain] &&
      content.fetch("image/png") == png && content.fetch("text/html") == "<b>日本語</b>" &&
      content.fetch("text/plain") == "日本語"
    from_child.puts "read"
    window.write_clipboard([Zaniah::Clipboard::Item.new("image/png" => png, "text/plain" => "reverse")])
    from_child.puts "owned"
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until IO.select([to_child], nil, nil, 0)
      raise "parent did not finish transfer" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      window.poll_events
      IO.select([to_child], nil, nil, 0.01)
    end
    raise "parent did not acknowledge transfer" unless to_child.gets == "done\n"
  rescue StandardError => error
    from_child.puts "error: #{error.full_message}"
    exit! 1
  ensure
    window&.close
    from_child.close
    to_child.close
  end
  exit! 0
end

to_child.close
from_child.close
commands.sync = true
window = nil
child_reaped = false
begin
  window = Zaniah::Platform::Linux::Window.new(width: 64, height: 64)
  window.write_clipboard([Zaniah::Clipboard::Item.new("text/plain" => "日本語", "text/html" => "<b>日本語</b>", "image/png" => png)])
  commands.puts "read"
  2.times do |index|
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until IO.select([responses], nil, nil, 0)
      raise "X11 clipboard transfer timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      window.poll_events
      IO.select([responses], nil, nil, 0.01)
    end
    expected = index.zero? ? "read\n" : "owned\n"
    reply = responses.gets
    raise "X11 clipboard transfer failed: #{reply}" unless reply == expected
  end
  content = window.read_clipboard(types: %w[text/plain image/png])
  raise "X11 incremental clipboard read failed" unless content.fetch("text/plain") == "reverse" && content.fetch("image/png") == png
  commands.puts "done"
  Process.waitpid(child)
  child_reaped = true
  raise "X11 clipboard child failed" unless $?.success?
  puts "X11 typed clipboard roundtrip passed"
ensure
  window&.close
  commands.close
  responses.close
  if !child_reaped && Process.waitpid(child, Process::WNOHANG).nil?
    Process.kill("TERM", child)
    Process.waitpid(child)
  end
end
