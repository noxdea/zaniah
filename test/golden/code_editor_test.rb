# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class CodeEditorGoldenTest < Zaniah::UITest
  class Syntax
    def tokens(_index, text)
      matches = []
      text.to_enum(:scan, /\b(?:def|return|compute)\b|\d+/).each do
        match = Regexp.last_match
        matches << [match.begin(0)...match.end(0), match[0].match?(/\A\d/) ? :number : :keyword]
      end
      matches
    end
    def edited(*) = nil
  end

  %i[dark light high_contrast].each do |appearance|
    define_method("test_wrapped_line_numbers_#{appearance}") do
      assert_golden("text/code-editor-wrap-#{appearance}", theme: appearance) do
        theme = @app.global(:theme)
        editor = Zaniah::UI::CodeEditor.new("def compute(value)\n  return value + 123\nend",
          highlighter: Syntax.new, wrap: true).w(110).h(160)
        Zaniah::Div.new.w_full.h_full.p(24).bg(theme.colors.background).child(editor)
      end
    end
  end
end
