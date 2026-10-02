# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class NamedComponentsTest < Minitest::Test
  def setup
    @app = Zaniah::App.new(clock: -> { 0.0 })
    @window = @app.open_window(width: 800, height: 700)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def test_tables_trees_and_segment_groups_expose_supplied_names
    source = Object.new
    def source.count = 1
    def source.cell(*) = "packet"
    components = [
      [Zaniah::UI::VirtualTable.new(source, columns: [:info], label: "Packets"), :table, "Packets"],
      [Zaniah::UI::TreeView.new([{id: "ip", label: "IPv4"}], label: "Packet details"), :tree, "Packet details"],
      [Zaniah::UI::SegmentedControl.new(%w[Hex Text], label: "Search mode"), :radiogroup, "Search mode"],
      [Zaniah::UI::PropertyGrid.new([{key: :enabled, type: :boolean}], {enabled: true}, label: "Capture settings"), :table, "Capture settings"]
    ]
    components.each do |component, role, label|
      @window.render(component, present: false)
      node = @window.accessibility_tree.root
      assert_equal role, node.role
      assert_equal label, node.label
    end
    toolbar = Zaniah::UI::Toolbar.new(Zaniah::UI::Button.new("Open")).accessibility_label("Capture controls")
    @window.render(toolbar, present: false)
    assert_equal "Capture controls", @window.accessibility_tree.root.label
  end

  def test_every_property_editor_inherits_its_schema_label
    schema = [
      {key: :name, label: "Name", type: :text}, {key: :description, label: "Description", type: :textarea},
      {key: :limit, label: "Limit", type: :number}, {key: :enabled, label: "Enabled", type: :boolean},
      {key: :format, label: "Format", type: :select, options: %w[raw text]}, {key: :color, label: "Color", type: :color},
      {key: :date, label: "Date", type: :date}, {key: :time, label: "Time", type: :time}
    ]
    values = {name: "Capture", description: "Trace", limit: 10, enabled: true, format: "raw", color: "#2563eb", date: Date.today, time: "12:00"}
    @window.render(Zaniah::UI::PropertyGrid.new(schema, values, height: 600, label: "Settings"), present: false)
    snapshot = Zaniah::Inspection.snapshot(@window)
    schema.each do |property|
      role = property[:type] == :boolean ? :checkbox : %i[select color date time].include?(property[:type]) ? :combobox : :textbox
      assert snapshot.accessibility.query(role: role, label: property[:label]).any?, property[:label]
    end
  end

  def test_dialog_close_and_palette_names_can_be_localized
    dialog = Zaniah::UI::Dialog.new(Zaniah::UI::Button.new("続行"), title: "確認", close_label: "閉じる")
    @window.render(dialog, present: false)
    snapshot = Zaniah::Inspection.snapshot(@window)
    close_node = snapshot.accessibility.query(role: :button, label: "閉じる").first&.first
    refute_nil close_node
    assert Zaniah::Inspection.perform(@window, close_node, :press)
    refute dialog.open?
    palette = Zaniah::UI::CommandPalette.new([["開く", ->(*) {}]], open: true, title: "コマンド", placeholder: "検索", close_label: "閉じる")
    @window.render(palette, present: false)
    snapshot = Zaniah::Inspection.snapshot(@window)
    assert snapshot.accessibility.query(role: :dialog, label: "コマンド").any?
    assert snapshot.accessibility.query(role: :list, label: "コマンド").any?
    assert snapshot.accessibility.query(role: :searchbox, label: "検索").any?
    assert_equal :searchbox, palette.accessibility_node(nil).children.first.role
    assert_equal :list, palette.accessibility_node(nil).children.last.role
    assert snapshot.accessibility.query(role: :button, label: "閉じる").any?
  end
end
