# frozen_string_literal: true

module Zaniah
  module Input
    module Keystroke
      ORDER = %w[ctrl alt shift cmd].freeze
      ALIASES = {"control" => "ctrl", "option" => "alt", "meta" => "cmd", "super" => "cmd",
                 "return" => "enter", "escape" => "esc", " " => "space"}.freeze

      def self.normalize(value)
        words = value.downcase.split("-")
        key = value.end_with?("--") ? "-" : words.pop
        key = "-" if key.nil? || key.empty?
        modifiers = words.map { |word| ALIASES.fetch(word, word) }
        raise ArgumentError, "unknown key modifier" unless (modifiers - ORDER).empty?
        (ORDER.select { |modifier| modifiers.include?(modifier) } << ALIASES.fetch(key, key)).join("-")
      end
    end
  end
end
