# frozen_string_literal: true

require "tmpdir"
require "rbconfig"

Dir.mktmpdir("zaniah-linux-") do |directory|
  log = File.open(File.join(directory, "display.log"), "w")
  ENV["LIBGL_ALWAYS_SOFTWARE"] = "1"
  wayland = ARGV.include?("--wayland")
  if wayland
    ENV["XDG_RUNTIME_DIR"] = directory
    ENV["WAYLAND_DISPLAY"] = "wayland-zaniah"
    ENV.delete("DISPLAY")
    pid = Process.spawn("weston", "--backend=headless-backend.so", "--renderer=gl", "--socket=wayland-zaniah", "--idle-time=0", out: log, err: log)
    socket = File.join(directory, "wayland-zaniah")
  else
    ENV["ZANIAH_CHECK_INPUT"] = "1"
    ENV["ZANIAH_CHECK_DPI"] = "1"
    ENV.delete("WAYLAND_DISPLAY")
    number = 90 + Process.pid % 100
    ENV["DISPLAY"] = ":#{number}"
    pid = Process.spawn("Xvfb", ENV["DISPLAY"], "-screen", "0", "1280x800x24", "+extension", "GLX", out: log, err: log)
    socket = "/tmp/.X11-unix/X#{number}"
  end
  begin
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until File.socket?(socket)
      raise File.read(log.path) if Process.waitpid(pid, Process::WNOHANG)
      raise "display startup timeout: #{File.read(log.path)}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    if ARGV.include?("--ibus")
      raise "IBus check requires dbus-run-session and X11" if wayland || !ENV["DBUS_SESSION_BUS_ADDRESS"]
      ENV["XMODIFIERS"] = "@im=ibus"
      ENV["LANG"] = "C.UTF-8"
      system("ibus-daemon", "--daemonize", "--xim", "--panel=disable") or raise "IBus startup failed"
      sleep 1
      raise "native Japanese IME failed" unless system(RbConfig.ruby, File.join(__dir__, "native_ime.rb"))
      ENV["XMODIFIERS"] = "@im=none"
    end
    success = system(RbConfig.ruby, File.join(__dir__, "native_smoke.rb"), "--gl", "--check")
    raise "native rendering failed\n#{File.read(log.path)}" unless success
    raise "native XDND transfer failed" unless wayland || system(RbConfig.ruby, File.join(__dir__, "native_drop.rb"))
    raise "native watcher failed" unless system(RbConfig.ruby, File.join(__dir__, "native_watch.rb"))
    if ARGV.include?("--editor")
      raise "native editor integration failed" unless system(RbConfig.ruby, "--yjit", File.expand_path("../../canopus/tools/native_check.rb", __dir__), "--idle")
    end
  ensure
    Process.kill("TERM", pid) rescue Errno::ESRCH
    Process.wait(pid) rescue Errno::ECHILD
    log.close
  end
end
