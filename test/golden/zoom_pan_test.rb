# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"
require "zaniah/ui/zoom_pan_view"

class ZoomPanGoldenTest < Zaniah::UITest
  %i[dark light high_contrast].each do |appearance|
    define_method("test_zoom_pan_#{appearance}") do
      theme = Zaniah::Theme.public_send(appearance)
      assert_golden("components/zoom-pan-#{appearance}", theme: theme) do
        content = Zaniah::Div.new.w(180).h(120).p(12).bg(theme.colors.surface).rounded(8)
          .child(Zaniah::UI::Label.new("Canvas", size: :lg))
          .child(Zaniah::Div.new.w(120).h(42).bg(theme.colors.accent).rounded(4))
        Zaniah::Div.new.w_full.h_full.p(24).bg(theme.colors.background)
          .child(Zaniah::UI::ZoomPanView.new(content, zoom: 1.5).w(300).h(200))
      end
    end
  end
end
