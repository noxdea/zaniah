# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/tui/input_decoder"
require "stringio"

class TUIInputTest < Minitest::Test
  def decode(bytes)
    events = []
    decoder = Zaniah::Platform::TUI::InputDecoder.new { |event| events << event }
    bytes.b.bytes.each { |byte| decoder.feed(byte.chr) }
    [events, decoder]
  end

  def test_fragmented_unicode_paste_and_escape_timeout
    events, decoder = decode("日本\e[200~a\nb\e[D\e[201~\e")
    assert_equal ["日", "本", "a\nb\e[D"], events.map(&:text)
    assert decoder.flush_escape
    assert_equal "esc", events.last.keystroke
    refute decoder.flush_escape
    assert_empty decoder.buffer
  end

  def test_modifiers_navigation_function_keys_and_alt_unicode
    events, decoder = decode("\e[1;5D\e[3;3~\e[Z\eOP\eO1;6Q\e[24~\eé\0\e-")
    assert_equal %w[ctrl-left alt-delete shift-tab f1 ctrl-shift-f2 f12 alt-é ctrl-space alt--], events.map(&:keystroke)
    assert_empty decoder.buffer
  end

  def test_sgr_mouse_drag_release_wheel_and_following_text
    events, decoder = decode("\e[<16;3;4M\e[<48;4;4M\e[<16;4;4m\e[<65;4;4M\e[<66;4;4Mq")
    down, drag, up, wheel, horizontal, text = events
    assert_instance_of Zaniah::Input::MouseDown, down
    assert_equal Zaniah::Point.new(20, 70), down.position
    assert_equal [:left, ["ctrl"]], [down.button, down.modifiers]
    assert_instance_of Zaniah::Input::MouseMove, drag
    assert_instance_of Zaniah::Input::MouseUp, up
    assert_equal Zaniah::Point.new(0, 40), wheel.delta
    assert_equal Zaniah::Point.new(-40, 0), horizontal.delta
    assert_equal "q", text.text
    assert_empty decoder.buffer
  end

  def test_unknown_controls_and_invalid_utf8_do_not_stall_input
    events, decoder = decode("\e[?999h\e]0;ignored\a\ePignored\e\\\xffa".b)
    assert_equal ["�", "a"], events.map(&:text)
    assert_empty decoder.buffer
    assert_raises(Zaniah::Error) { decoder.feed("\e[" + "1" * 1025) }
  end

  def test_csi_unicode_repeat_release_and_modify_other_keys
    events, = decode("\e[97;5:2u\e[97;5:3u\e[27;3;120~\e[26085u")
    assert_equal "ctrl-a", events[0].keystroke
    assert events[0].is_held
    assert_instance_of Zaniah::Input::KeyUp, events[1]
    assert_equal "alt-x", events[2].keystroke
    assert_equal "日", events[3].text
  end

  def test_tui_window_uses_decoder_and_retains_bracketed_paste
    window = Zaniah::Platform::TUI::Window.new(input: StringIO.new, output: StringIO.new, width: 320, height: 200)
    events = []
    window.on_input { |event| events << event }
    window.feed_input("\e[<0;2;2M\e[15;5~\e[200~日本\e[201~")
    assert_instance_of Zaniah::Input::MouseDown, events.first
    assert_equal "ctrl-f5", events[1].keystroke
    assert_equal "日本", events[2].text
  ensure
    window&.close
  end

  def test_real_pty_raw_loop_mouse_modes_and_escape_timeout
    skip "Unix PTY is not available on Windows" if RUBY_PLATFORM.match?(/mingw|mswin/)
    require "pty"
    require "rbconfig"
    child = <<~'RUBY'
      $stdout.sync = true
      window = Zaniah::Platform.open_window(backend: :tui, width: 160, height: 100)
      events = []
      window.on_input do |event|
        events << event
        window.close if event.is_a?(Zaniah::Input::KeyDown) && event.keystroke == "esc"
      end
      window.run
      raise "modified F key missing" unless events.any? { |event| event.is_a?(Zaniah::Input::KeyDown) && event.keystroke == "ctrl-f5" }
      raise "mouse missing" unless events.any? { |event| event.is_a?(Zaniah::Input::MouseDown) }
      raise "paste split" unless events.any? { |event| event.is_a?(Zaniah::Input::TextInput) && event.text == "日本\nx" }
      puts "TUI_INPUT_OK"
    RUBY
    PTY.spawn(RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", "-rzaniah", "-e", child) do |reader, writer, pid|
      output, sent = +"".b, false
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      until output.include?("TUI_INPUT_OK")
        raise "raw terminal check timed out: #{output.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        next unless IO.select([reader], nil, nil, 0.1)
        output << reader.readpartial(4096)
        if !sent && output.include?("\e[?1006h")
          writer.write("\e[15;5~\e[<0;3;2M\e[200~日本\nx\e[201~\e")
          writer.flush
          sent = true
        end
      end
      assert_includes output, "\e[?1006l\e[?1002l"
      assert Process.waitpid2(pid).last.success?
    ensure
      Process.kill("TERM", pid) rescue Errno::ESRCH
      Process.wait(pid) rescue Errno::ECHILD
    end
  end
end
