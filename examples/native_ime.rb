# frozen_string_literal: true

# Run inside a disposable D-Bus/X11 session with IBus and Mozc installed.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
require "open3"

window = Zaniah::Platform.open_window(backend: :linux, display_server: :x11, width: 400, height: 240, title: "IBus Japanese input check")
events = []
window.on_input { |event| events << event }
window.ime_state = Zaniah::Bounds.new(20, 30, 1, 20)
system("xdotool", "windowfocus", window.handle.to_s) or raise "focus failed"
ic = window.instance_variable_get(:@ic)
raise "XIM input context unavailable" unless ic
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  window.tick
  sleep 0.01
end
selector = Process.spawn("ibus", "engine", "mozc-on")
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
until (result = Process.waitpid2(selector, Process::WNOHANG))
  raise "IBus engine selection timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  window.tick
  sleep 0.01
end
current, = Open3.capture2e("ibus", "engine")
# IBus CLI may return 1 after success when Mozc's layout is "default".
# Its active engine, not setxkbmap's exit status, determines readiness.
raise "Mozc engine selection failed: #{result.last.inspect}, current=#{current.inspect}" unless current.strip == "mozc-on"
sender = Process.spawn("xdotool", "type", "--delay", "100", "nihon")
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  window.tick
  sleep 0.01
end
Process.wait(sender)
sender = Process.spawn("xdotool", "key", "space", "Return")
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  window.tick
  sleep 0.01
end
Process.wait(sender)
preedit = events.grep(Zaniah::Input::Composition).map(&:text)
committed = events.grep(Zaniah::Input::TextInput).map(&:text).join
raise "Japanese preedit missing: #{events.inspect}" unless preedit.any? { |text| text.match?(/[にほ日]/) }
raise "Japanese commit missing or duplicated: #{events.inspect}" unless ["日本", "にほん"].include?(committed)
puts "IBus/Mozc: preedit=#{preedit.inspect}, committed=#{committed.inspect}"
window.close
