# frozen_string_literal: true

require "json"
require_relative "keystroke"
require_relative "context_predicate"

module Zaniah
  module Input
    module StandardActions
      EDIT = %i[undo redo cut copy paste select_all].freeze
    end

    class Keymap
      class << self
        def default_ui(platform: RUBY_PLATFORM, **options)
          platform_defaults(platform, **options)
        end

        def platform_defaults(platform, **options)
          mac = platform.to_s.match?(/darwin|mac/)
          windows = platform.to_s.match?(/mingw|mswin|windows/)
          tui = platform.to_s == "tui"
          primary = mac ? "cmd" : "ctrl"
          map = new(**options)
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
            .bind("up", :previous_option, context: "in_list")
            .bind("down", :next_option, context: "in_list")
            .bind("left", :move_left, context: "in_text_field")
            .bind("right", :move_right, context: "in_text_field")
            .bind("shift-left", :select_left, context: "in_text_field")
            .bind("shift-right", :select_right, context: "in_text_field")
            .bind("home", :line_start, context: "in_text_field")
            .bind("end", :line_end, context: "in_text_field")
            .bind("shift-home", :select_line_start, context: "in_text_field")
            .bind("shift-end", :select_line_end, context: "in_text_field")
            .bind("backspace", :delete_backward, context: "in_text_field")
            .bind("delete", :delete_forward, context: "in_text_field")
            .bind("enter", :insert_newline, context: "in_text_field")
            .bind("left", :decrement, context: "in_slider")
            .bind("down", :decrement, context: "in_slider")
            .bind("right", :increment, context: "in_slider")
            .bind("up", :increment, context: "in_slider")
            .bind("home", :minimum, context: "in_slider")
            .bind("end", :maximum, context: "in_slider")
            .bind("pageup", :increment_page, context: "in_slider")
            .bind("pagedown", :decrement_page, context: "in_slider")
            .bind("up", :previous_option, context: "in_menu || in_tabs")
            .bind("left", :previous_option, context: "in_menu || in_tabs")
            .bind("down", :next_option, context: "in_menu || in_tabs")
            .bind("right", :next_option, context: "in_menu || in_tabs")
            .bind("home", :first, context: "in_menu || in_tabs")
            .bind("end", :last, context: "in_menu || in_tabs")
            .bind("up", :previous_option, context: "in_tree")
            .bind("down", :next_option, context: "in_tree")
            .bind("home", :first, context: "in_tree")
            .bind("end", :last, context: "in_tree")
            .bind("left", :collapse, context: "in_tree")
            .bind("right", :expand, context: "in_tree")
            .bind("alt-up", :reorder_before, context: "reorderable")
            .bind("alt-down", :reorder_after, context: "reorderable")
            .bind("esc", :cancel_reorder, context: "reorderable")
            .bind("up", :previous_option, context: "in_table")
            .bind("down", :next_option, context: "in_table")
            .bind("shift-up", :extend_previous, context: "in_table")
            .bind("shift-down", :extend_next, context: "in_table")
            .bind("home", :first, context: "in_table")
            .bind("end", :last, context: "in_table")
            .bind("pageup", :page_up, context: "in_table")
            .bind("pagedown", :page_down, context: "in_table")
            .bind("up", :previous_option, context: "in_grid")
            .bind("down", :next_option, context: "in_grid")
            .bind("left", :previous_column, context: "in_grid")
            .bind("right", :next_column, context: "in_grid")
            .bind("shift-up", :extend_previous, context: "in_grid")
            .bind("shift-down", :extend_next, context: "in_grid")
            .bind("shift-left", :extend_column_previous, context: "in_grid")
            .bind("shift-right", :extend_column_next, context: "in_grid")
            .bind("home", :first, context: "in_grid")
            .bind("end", :last, context: "in_grid")
            .bind("enter", :activate, context: "in_grid")
            .bind("up", :previous_option, context: "in_combobox")
            .bind("down", :next_option, context: "in_combobox")
            .bind("home", :first, context: "in_combobox")
            .bind("end", :last, context: "in_combobox")
            .bind("enter", :choose_option, context: "in_combobox")
            .bind("esc", :dismiss, context: "in_combobox")
            .bind("up", :previous_option, context: "in_palette")
            .bind("down", :next_option, context: "in_palette")
            .bind("enter", :choose_option, context: "in_palette")
            .bind("left", :previous_option, context: "in_chart")
            .bind("right", :next_option, context: "in_chart")
            .bind("home", :first, context: "in_chart")
            .bind("end", :last, context: "in_chart")
            .bind("up", :line_up, context: "in_text_field && multiline")
            .bind("down", :line_down, context: "in_text_field && multiline")
          return map if tui

          word = mac ? "alt" : "ctrl"
          map.bind("#{primary}-a", :select_all)
            .bind("#{primary}-z", :undo)
            .bind("#{primary}-shift-z", :redo)
            .bind("#{primary}-x", :cut)
            .bind("#{primary}-c", :copy)
            .bind("#{primary}-v", :paste)
            .bind("#{word}-left", :word_left, context: "in_text_field")
            .bind("#{word}-right", :word_right, context: "in_text_field")
            .bind("#{word}-shift-left", :select_word_left, context: "in_text_field")
            .bind("#{word}-shift-right", :select_word_right, context: "in_text_field")
            .bind(mac ? "cmd-up" : "ctrl-home", :document_start, context: "in_text_field")
            .bind(mac ? "cmd-down" : "ctrl-end", :document_end, context: "in_text_field")
          map.bind("ctrl-y", :redo) if windows
          map
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

      def shortcut_for(action)
        @bindings.reverse_each.find { |binding|
          same_action = binding.action == action ||
            ((binding.action.is_a?(Symbol) || binding.action.is_a?(String)) && binding.action.to_s == action.to_s)
          same_action && binding.predicate.call({})
        }&.keys&.join(" ")
      end
    end
  end
end

require_relative "keymap/binding"
