# frozen_string_literal: true

require_relative "../test_helper"

class GoldenThemeTest < Zaniah::UITest
  %i[dark light].each do |appearance|
    define_method("test_#{appearance}_theme") do
      assert_golden("theme/#{appearance}", theme: appearance) do
        theme = @app.global(:theme)
        Zaniah::Div.new.w(220).h(80).p(16).bg(theme.colors.surface)
          .border(1).border_color(theme.colors.border).rounded(theme.radii[:md])
          .child(Zaniah::Text.new("#{appearance.capitalize} theme", size: 18, color: theme.colors.text))
      end
    end
  end
end
