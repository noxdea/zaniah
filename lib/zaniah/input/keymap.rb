# frozen_string_literal: true

require "json"
require_relative "keystroke"
require_relative "context_predicate"

module Zaniah
  module Input
    class Keymap
      class << self
        def default_ui(platform: RUBY_PLATFORM, **options)
          platform_defaults(platform, **options)
        end

        def platform_defaults(platform, **options)
          primary = platform.to_s.match?(/darwin|mac/) ? "cmd" : "ctrl"
          new(**options)
            .bind("tab", :focus_next)
            .bind("shift-tab", :focus_previous)
            .bind("left", :focus_left, context: "!in_text_field && !in_list")
            .bind("right", :focus_right, context: "!in_text_field && !in_list")
            .bind("up", :focus_up, context: "!in_text_field && !in_list")
            .bind("down", :focus_down, context: "!in_text_field && !in_list")
            .bind("enter", :activate)
            .bind("space", :activate, context: "!in_text_field")
            .bind("esc", :dismiss)
            .bind("home", :first, context: "in_list")
            .bind("end", :last, context: "in_list")
            .bind("pageup", :page_up, context: "in_list")
            .bind("pagedown", :page_down, context: "in_list")
            .bind("#{primary}-a", :select_all, context: "in_text_field || in_list")
        end
      end

      def initialize(timeout: 1.0, clock: MONOTONIC_CLOCK)
        @bindings, @pending, @last_time, @timeout, @clock = [], [], 0, timeout, clock
      end

      def bind(keys, action, context: "")
        @bindings << Binding.new(keys.split.map { |key| Keystroke.normalize(key) }, ContextPredicate.new(context), action)
        self
      end

      def load_json(text)
        JSON.parse(text).each do |group|
          group.fetch("bindings").each { |key, action| bind(key, action, context: group.fetch("context", "")) }
        end
        self
      end

      def dispatch(key, context: {}, now: @clock.call)
        @pending.clear if now - @last_time > @timeout
        @last_time = now
        key = Keystroke.normalize(key)
        @pending << key
        candidates = @bindings.reverse.select { |binding| binding.predicate.call(context) && binding.keys.first(@pending.length) == @pending }
        if candidates.empty? && @pending.length > 1
          @pending.replace([key])
          candidates = @bindings.reverse.select { |binding| binding.predicate.call(context) && binding.keys.first(1) == @pending }
        end
        # The newest matching prefix also overrides an older complete binding.
        # Otherwise a default ctrl-k action makes a later ctrl-k ctrl-s unusable.
        match = candidates.first
        if match && match.keys.length == @pending.length
          @pending.clear
          match.action
        elsif candidates.empty?
          @pending.clear
          nil
        else
          :pending
        end
      end

      def bindings = @bindings.dup.freeze
    end
  end
end

require_relative "keymap/binding"
