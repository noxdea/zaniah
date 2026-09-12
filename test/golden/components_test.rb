# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class ComponentGoldenTest < Zaniah::UITest
  def component_sheet
    theme = @app.global(:theme)
    buttons = %i[primary secondary ghost danger].flat_map do |variant|
      %i[sm md lg].map { |size| Zaniah::UI::Button.new("#{variant} #{size}", variant: variant, size: size) }
    end
    inputs = [
      Zaniah::UI::Checkbox.new("Checked", value: true), Zaniah::UI::Radio.new("Selected", value: true),
      Zaniah::UI::Switch.new("Enabled", value: true), Zaniah::UI::Slider.new(value: 65),
      Zaniah::UI::ProgressBar.new(value: 55), Zaniah::UI::TextField.new("Ruby", label: "Name")
    ]
    basics = [Zaniah::UI::Badge.new("New", variant: :accent), Zaniah::UI::Avatar.new("Ruby UI"),
      Zaniah::UI::Skeleton.new(width: 100), Zaniah::UI::EmptyState.new("Nothing here", message: "Create the first item")]
    Zaniah::Div.new.p(theme.spacing[4]).gap(theme.spacing[3]).bg(theme.colors.background)
      .child(Zaniah::Div.new.flex_row.style(flex_wrap: :wrap).gap(theme.spacing[2]).children(buttons))
      .child(Zaniah::UI::Divider.new)
      .child(Zaniah::Div.new.flex_row.style(flex_wrap: :wrap).gap(theme.spacing[3]).children(inputs))
      .child(Zaniah::Div.new.flex_row.items_center.gap(theme.spacing[3]).children(basics))
  end

  def test_component_sheet_dark = assert_golden("components/sheet-dark", theme: :dark) { component_sheet }
  def test_component_sheet_light = assert_golden("components/sheet-light", theme: :light) { component_sheet }
end
