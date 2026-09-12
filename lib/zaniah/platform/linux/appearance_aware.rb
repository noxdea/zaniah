# frozen_string_literal: true

require "open3"

module Zaniah
  module Platform
    module Linux
      module AppearanceAware
        PORTAL = ["--session", "--dest", "org.freedesktop.portal.Desktop", "--object-path", "/org/freedesktop/portal/desktop"].freeze
        def appearance
          output, status = Open3.capture2e("gdbus", "call", *PORTAL, "--timeout", "1", "--method", "org.freedesktop.portal.Settings.Read", "org.freedesktop.appearance", "color-scheme")
          return :dark if status.success? && output.match?(/uint32\s+1\b/)
          return :light if status.success? && output.match?(/uint32\s+2\b/)
          output, status = Open3.capture2e("gsettings", "get", "org.gnome.desktop.interface", "color-scheme")
          status.success? && output.include?("prefer-dark") ? :dark : :light
        rescue Errno::ENOENT
          ENV.fetch("GTK_THEME", "").downcase.include?("dark") ? :dark : :light
        end

        def reduced_motion?
          return @reduced_motion if instance_variable_defined?(:@reduced_motion)
          output, status = Open3.capture2e("gsettings", "get", "org.gnome.desktop.interface", "enable-animations")
          @reduced_motion = status.success? && output.strip == "false"
        rescue Errno::ENOENT
          @reduced_motion = false
        end

        def on_appearance(&block)
          @on_appearance = block
          close_appearance
          return unless block
          stdin, @appearance_io, @appearance_process = Open3.popen2e("gdbus", "monitor", *PORTAL)
          stdin.close
          @appearance_buffer = +""
        rescue Errno::ENOENT
          # Minimal desktops without GIO still use the initial GTK_THEME value.
          nil
        end

        def poll_appearance
          return unless @appearance_io
          data = @appearance_io.read_nonblock(8192, exception: false)
          return close_appearance if data.nil?
          return unless data.is_a?(String)
          @appearance_buffer << data
          while (newline = @appearance_buffer.index("\n"))
            line = @appearance_buffer.slice!(0, newline + 1)
            next unless line.include?("SettingChanged") && line.include?("color-scheme")
            @on_appearance&.call(line.match?(/uint32\s+1\b/) ? :dark : :light)
            request_frame
          end
          @appearance_buffer.clear if @appearance_buffer.bytesize > 65_536
        rescue IOError
          close_appearance
        end

        def close_appearance
          @appearance_io&.close unless @appearance_io&.closed?
          if @appearance_process&.alive?
            Process.kill("TERM", @appearance_process.pid) rescue Errno::ESRCH
            @appearance_process.join(0.2)
          end
          @appearance_io = @appearance_process = nil
        end
      end
    end
  end
end
