# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class ExtendedComponentGoldenTest < Zaniah::UITest
  def component(name)
    case name
    when :segmented_control then Zaniah::UI::SegmentedControl.new([["Day", :day], ["Week", :week], ["Month", :month]], value: :week)
    when :alert then Zaniah::UI::Alert.new("Export complete", message: "Your file is ready", variant: :success, dismissible: true, live: true)
    when :hover_card then Zaniah::UI::HoverCard.new(Zaniah::UI::Label.new("Keyboard shortcuts"), anchor: Zaniah::Bounds.new(40, 40, 140, 32)).open
    when :calendar then Zaniah::UI::Calendar.new(value: "2026-09-24", week_start: 1)
    when :date_range_picker then Zaniah::UI::DateRangePicker.new(value: ["2026-09-01", "2026-09-30"])
    end
  end

  %i[dark light high_contrast].each do |appearance|
    %i[segmented_control alert hover_card calendar date_range_picker].each do |name|
      define_method("test_#{name}_#{appearance}") do
        fixture = {alert: "alert_success", calendar: "calendar_month"}.fetch(name, name.to_s)
        assert_golden("components/#{fixture}-#{appearance}", theme: appearance) do
          theme = @app.global(:theme)
          Zaniah::Div.new.w_full.h_full.p(28).bg(theme.colors.background).child(component(name))
        end
      end
    end
  end
end
