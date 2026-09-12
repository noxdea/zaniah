# frozen_string_literal: true

require_relative "platform/display"
require_relative "platform/appearance"
require_relative "platform/headless/window"
require_relative "platform/tui/window"

module Zaniah
  module Platform
    def self.displays(backend: :auto, **options)
      backend = RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mswin|mingw/) ? :windows : :linux if backend == :auto
      return [] if [:headless, :tui].include?(backend)
      raise ArgumentError, "unknown platform #{backend}" unless [:mac, :linux, :windows].include?(backend)
      require_relative "platform/#{backend}"
      const_get(backend.to_s.capitalize).displays(**options)
    end

    def self.watch(paths, latency: 0.05)
      platform = RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mswin|mingw/) ? :windows : :linux
      require_relative "platform/#{platform}/watcher"
      const_get(platform.to_s.capitalize)::Watcher.new(paths, latency: latency)
    end

    def self.open_window(backend: :headless, **options)
      case backend
      when :headless then Headless::Window.new(**options)
      when :tui then TUI::Window.new(**options)
      when :mac, :linux, :windows
        require_relative "platform/#{backend}"
        const_get(backend.to_s.capitalize)::Window.new(**options)
      else raise ArgumentError, "unknown platform #{backend}"
      end
    end
  end
end
