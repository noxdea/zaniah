# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class VerticalTextGoldenTest < Zaniah::UITest
  %i[dark light high_contrast].each do |appearance|
    define_method("test_vertical_ruby_#{appearance}") do
      assert_golden("text/vertical-ruby-#{appearance}", theme: appearance) do
        theme = @app.global(:theme)
        rich = Zaniah::UI::RichText.new([
          {text: "KAN", ruby: "RUBY", size: 28, color: theme.colors.text},
          {text: "12", combine_upright: true, size: 28, color: theme.colors.text},
          {text: " A B C", size: 28, color: theme.colors.text}
        ], writing_mode: :vertical_rl).h(120)
        Zaniah::Div.new.w_full.h_full.p(32).bg(theme.colors.background)
          .child(Zaniah::Div.new.w(240).h(180).p(18).bg(theme.colors.surface).child(rich))
      end
    end
  end
end
