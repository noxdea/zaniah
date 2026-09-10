# frozen_string_literal: true

require "prism"

module ProcessFixture
  def self.call(data)
    case data.fetch("op")
    when "echo" then data.fetch("value")
    when "pid" then Process.pid
    when "jit" then !!(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?)
    when "state" then @counter = (@counter || 0) + 1
    when "prism" then Prism.parse(data.fetch("text")).errors.map(&:message)
    when "frozen" then data.frozen? && data.fetch("value").frozen? && data.fetch("value").first.frozen?
    when "sleep"
      sleep data.fetch("seconds")
      Process.pid
    when "hang"
      Signal.trap("TERM", "IGNORE")
      loop { sleep 1 }
    when "crash" then exit! 7
    when "error" then raise ArgumentError, "fixture failure"
    when "object" then Object.new
    when "huge" then "x" * data.fetch("bytes")
    when "stdout"
      puts "handler chatter"
      STDOUT.puts "constant chatter"
      "ok"
    end
  end
end
