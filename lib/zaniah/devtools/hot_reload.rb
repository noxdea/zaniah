# frozen_string_literal: true

require_relative "../platform/file_event"

module Zaniah
  module DevTools
    class HotReload
      attr_reader :error

      def initialize(app, paths, watcher: nil, loader: nil, &on_reload)
        @app, @watcher = app, watcher || Platform.watch(paths)
        @loader, @on_reload, @closed = loader || ->(path) { load path }, on_reload, false
      end

      def poll
        return [] if @closed
        paths = @watcher.poll(timeout: 0).filter_map do |event|
          event.path if %i[created modified renamed].include?(event.kind) && event.path&.end_with?(".rb")
        end.uniq
        paths.each { |path| @loader.call(path) }
        unless paths.empty?
          @error = nil
          @on_reload&.call(paths.freeze)
          @app.windows.each(&:request_frame)
        end
        paths
      rescue StandardError => exception
        @error = exception
        @app.windows.each(&:request_frame)
        []
      end

      def close
        return if @closed
        @closed = true
        @watcher.close
      end
    end
  end
end
