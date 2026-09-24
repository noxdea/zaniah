# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../tui/components_test"
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

  def component_examples
    TUIComponentsTest.new(:unused).cases.transform_values(&:first).merge(
      Button: Zaniah::Div.new.flex_row.style(flex_wrap: :wrap).gap(8).children(
        %i[primary secondary ghost danger].product(%i[sm md lg]).map { |variant, size| Zaniah::UI::Button.new("#{variant} #{size}", variant: variant, size: size) } +
        [Zaniah::UI::Button.new("Disabled").disabled, Zaniah::UI::Button.new("Loading").loading,
          Zaniah::UI::Button.new("Leading").icon(:check), Zaniah::UI::Button.new("Trailing").icon(:check, position: :trailing)]),
      Checkbox: Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::Checkbox.new("Off"), Zaniah::UI::Checkbox.new("On", value: true),
        Zaniah::UI::Checkbox.new("Mixed", value: :mixed), Zaniah::UI::Checkbox.new("Disabled", disabled: true)]),
      Radio: Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::Radio.new("Off"), Zaniah::UI::Radio.new("On", value: true), Zaniah::UI::Radio.new("Disabled", disabled: true)]),
      Switch: Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::Switch.new("Off"), Zaniah::UI::Switch.new("On", value: true), Zaniah::UI::Switch.new("Disabled", disabled: true)]),
      ProgressBar: Zaniah::Div.new.gap(12).children([
        Zaniah::UI::ProgressBar.new(value: 40), Zaniah::UI::ProgressBar.new]),
      Select: Zaniah::Div.new.flex_row.gap(12).children([
        Zaniah::UI::Select.new([["Ruby", :ruby]], value: :ruby), Zaniah::UI::Select.new(["Ruby"], disabled: true)]),
      DatePicker: Zaniah::Div.new.gap(8).children([
        Zaniah::UI::DatePicker.new("2026-09-13"), Zaniah::UI::DatePicker.new("2026-09-13", disabled: true)]),
      TimePicker: Zaniah::Div.new.gap(8).children([
        Zaniah::UI::TimePicker.new("14:30"), Zaniah::UI::TimePicker.new("14:30", disabled: true)]),
      ColorPicker: Zaniah::Div.new.gap(8).children([
        Zaniah::UI::ColorPicker.new("#2563eb"), Zaniah::UI::ColorPicker.new("#16a34a", disabled: true)])
    )
  end

  %i[dark light].each do |appearance|
    TUIComponentsTest.new(:unused).cases.each_key do |name|
      define_method("test_#{name.to_s.downcase}_#{appearance}") do
        theme = Zaniah::Theme.public_send(appearance)
        theme = theme.with(motion: theme.motion.with(reduced: true))
        assert_golden("components/#{name.to_s.gsub(/([a-z\d])([A-Z])/, '\\1-\\2').downcase}-#{appearance}", theme: theme) do
          theme = @app.global(:theme)
          Zaniah::Div.new.w_full.h_full.p(20).bg(theme.colors.background).child(component_examples.fetch(name))
        end
      end
    end
  end

  %i[dark light high_contrast].each do |appearance|
    define_method("test_command_palette_match_#{appearance}") do
      theme = Zaniah::Theme.public_send(appearance)
      palette = Zaniah::UI::CommandPalette.new(Array.new(6) { |index| ["Ruby command #{index}", ->(*) { }] }, open: true)
      palette.instance_variable_set(:@query, "Ru")
      root = Zaniah::Div.new.w_full.h_full.p(20).bg(theme.colors.background).child(palette)
      @app.global(:theme, theme)
      @window.render(root, present: false)
      @clock.advance(1)

      assert_golden("components/command-palette-match-#{appearance}", theme: theme) { root }
    end
  end
end
