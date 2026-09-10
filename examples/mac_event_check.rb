# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "zaniah"
abort "Cocoa requires macOS" unless RUBY_PLATFORM.include?("darwin")

window = Zaniah::Platform.open_window(backend: :mac, width: 320, height: 200, title: "Cocoa input and resize check")
objc = Zaniah::FFI::ObjC
app = Zaniah::Platform::Mac::App.instance
events = []
window.on_input { |event| events << event }
window.tick

# Exercise the actual NSTextInputClient callbacks without changing the user's
# selected keyboard input source. Interactive IME conversion remains separate.
window.ime_state = Zaniah::Bounds.new(20, 30, 1, 18)
objc.send(window.view, "setMarkedText:selectedRange:replacementRange:", objc.string("にほん"),
  [3, 0], [Zaniah::Platform::Mac::NS_NOT_FOUND, 0], args: [:pointer, :range, :range], result: :void)
raise "preedit callback missing" unless events.last.is_a?(Zaniah::Input::Composition) && events.last.text == "にほん"
candidate = -> { objc.send(window.view, "firstRectForCharacterRange:actualRange:", [0, 1], 0, args: [:range, :pointer], result: :rect) }
before = candidate.call
frame = objc.send(window.handle, "frame", result: :rect)
objc.send(window.handle, "setFrameOrigin:", [frame[0] + 25, frame[1] + 30], args: [:point], result: :void)
window.tick
moved = candidate.call
raise "IME candidate did not follow window move" unless (moved[0] - before[0] - 25).abs < 0.01 && (moved[1] - before[1] - 30).abs < 0.01
frame = objc.send(window.handle, "frame", result: :rect)
objc.send(window.handle, "setContentSize:", [400, 260], args: [:size], result: :void)
window.tick
raise "native resize was not delivered" unless window.content_size == Zaniah::Size.new(400, 260)
after_frame = objc.send(window.handle, "frame", result: :rect)
resized = candidate.call
raise "IME candidate did not follow resize" unless (resized[1] - moved[1] - (after_frame[1] - frame[1]) - 60).abs < 0.01 && resized.last(2) == [1, 18]
objc.send(window.view, "insertText:replacementRange:", objc.string("日本"),
  [Zaniah::Platform::Mac::NS_NOT_FOUND, 0], args: [:pointer, :range], result: :void)
raise "commit callback missing" unless events.last.is_a?(Zaniah::Input::TextInput) && events.last.text == "日本"

number = objc.send(window.handle, "windowNumber", result: :long)
post_key = lambda do |type|
  event = objc.send(objc.klass("NSEvent"), "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:",
    type, [0, 0], 0, Process.clock_gettime(Process::CLOCK_MONOTONIC), number, 0,
    objc.string("a"), objc.string("a"), 0, 0,
    args: [:ulong, :point, :ulong, :double, :long, :pointer, :pointer, :pointer, :bool, :uint])
  objc.send(app.handle, "postEvent:atStart:", event, 0, args: [:pointer, :bool], result: :void)
end

# A standalone tick still drains events. The run loop also drains the entire
# queue before its tick callback, with no second blocking/nonblocking poll.
post_key.call(10)
window.tick
raise "standalone tick did not deliver key down" unless events.grep(Zaniah::Input::KeyDown).any? { |event| event.keystroke == "a" }
post_key.call(11)
post_key.call(10)
post_key.call(11)
window.on_tick do
  raise "queued key events were delayed" unless events.grep(Zaniah::Input::KeyUp).count { |event| event.keystroke == "a" } == 2
  raise "queued key down duplicated" unless events.grep(Zaniah::Input::KeyDown).count { |event| event.keystroke == "a" } == 2
  window.close
end
window.run
puts "Cocoa: queued key down/up, standalone tick, run, Japanese composition/commit and moved/resized IME rectangles passed"
