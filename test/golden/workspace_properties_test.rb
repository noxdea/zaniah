# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class WorkspacePropertiesGoldenTest < Zaniah::UITest
  %i[dark light high_contrast].each do |appearance|
    define_method("test_dock_workspace_#{appearance}") do
      theme = Zaniah::Theme.public_send(appearance)
      layout = Zaniah::UI::DockLayout.split(id: :root, orientation: :horizontal, ratio: 0.4,
        first: Zaniah::UI::DockLayout.tabs(id: :files, panels: %i[Files Search]),
        second: Zaniah::UI::DockLayout.tabs(id: :edit, panels: %i[Editor Preview]))
      assert_golden("components/dock_workspace-#{appearance}", theme: theme) do
        Zaniah::Div.new.w_full.h_full.p(24).bg(theme.colors.background)
          .child(Zaniah::UI::DockWorkspace.new(layout,
            render: ->(id) { Zaniah::Div.new.p(12).child(Zaniah::UI::Label.new("#{id} panel")) }).w(600).h(300))
      end
    end

    define_method("test_property_grid_#{appearance}") do
      theme = Zaniah::Theme.public_send(appearance)
      schema = [{key: :title, label: "Title", type: :text},
        {key: :count, label: "Count", type: :number},
        {key: :visible, label: "Visible", type: :boolean}]
      assert_golden("components/property_grid-#{appearance}", theme: theme) do
        Zaniah::Div.new.w_full.h_full.p(24).bg(theme.colors.background)
          .child(Zaniah::UI::PropertyGrid.new(schema, {title: "Workspace", count: 3, visible: true}, height: 240).w(600))
      end
    end
  end
end
