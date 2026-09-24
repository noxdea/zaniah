# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class KbdGoldenTest < Zaniah::UITest
  %i[dark light high_contrast].each do |appearance|
    define_method("test_kbd_#{appearance}") do
      theme = Zaniah::Theme.public_send(appearance)
      assert_golden("components/kbd-variants-#{appearance}", theme: theme) do
        Zaniah::Div.new.w_full.h_full.p(20).bg(theme.colors.background)
          .child(Zaniah::Div.new.flex_row.gap(12).children([
            Zaniah::UI::Kbd.new("ctrl-shift-p", platform: :windows),
            Zaniah::UI::Kbd.new("ctrl-k ctrl-s", platform: :windows)
          ]))
      end
    end
  end
end
