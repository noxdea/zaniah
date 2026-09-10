# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
require "tmpdir"

platform = RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mingw|mswin/) ? :windows : :linux
require "zaniah/platform/#{platform}/watcher"
Dir.mktmpdir("zaniah-watch-") do |directory|
  watcher = Zaniah::Platform.const_get(platform.to_s.capitalize)::Watcher.new(directory)
  begin
    path = File.join(directory, "native-event.txt")
    File.write(path, "filesystem notification")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    events = []
    loop do
      events.concat(watcher.poll(timeout: 0.05))
      break if events.any? { |event| event.path&.end_with?("native-event.txt") }
      raise "native watcher received no file event: #{events.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    end
    puts events.inspect
  ensure
    watcher.close
  end
end
