# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class WorkspacePropertiesTest < Minitest::Test
  include Zaniah::InteractionHelper

  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 800, height: 600)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def layout
    Zaniah::UI::DockLayout.split(id: :root, orientation: :horizontal, ratio: 0.4,
      first: Zaniah::UI::DockLayout.tabs(id: :left, panels: %i[files search]),
      second: Zaniah::UI::DockLayout.tabs(id: :right, panels: [:editor]))
  end

  def test_dock_layout_round_trip_and_validation
    assert_equal layout.to_h, Zaniah::UI::DockLayout.from_h(layout.to_h).to_h
    assert_raises(ArgumentError) { Zaniah::UI::DockLayout.from_h(type: :tabs, id: :empty, panels: []) }
    assert_raises(ArgumentError) { Zaniah::UI::DockLayout.from_h(type: :split, id: :root,
      orientation: :horizontal, ratio: 0.5, first: {type: :tabs, id: :a, panels: [:same]},
      second: {type: :tabs, id: :b, panels: [:same]}) }
    assert_raises(ArgumentError) { Zaniah::UI::DockLayout.from_h(type: :split, id: :root,
      ratio: 0.5, first: {type: :tabs, id: :a, panels: [:a]}, second: {type: :tabs, id: :b, panels: [:b]}) }
    assert_raises(ArgumentError) { Zaniah::UI::DockLayout.from_h(type: :split, id: :root,
      orientation: :vertical, ratio: 1.0, first: {type: :tabs, id: :a, panels: [:a]},
      second: {type: :tabs, id: :b, panels: [:b]}) }
  end

  def test_dock_move_split_detach_and_semantics
    changes, detached = [], []
    dock = Zaniah::UI::DockWorkspace.new(layout, render: ->(id) { Zaniah::UI::Label.new(id) })
      .on_layout_change { |next_layout, _| changes << next_layout.to_h }
      .on_detach { |id, _| detached << id }
    @window.render(dock, present: false)
    semantic = @window.accessibility_tree.root
    assert_equal :group, semantic.role
    roles = walk_roles(semantic)
    %i[tablist tab tabpanel separator].each { |role| assert_includes roles, role }
    assert_includes dock.tui_cells, "[(files)|search]"
    assert dock.select(:search)
    assert dock.move(:search, to: :right)
    assert_equal %w[editor search], dock.layout.find_group(:right).panels
    assert dock.split(:search, target: :right, side: :bottom)
    assert_equal 3, dock.layout.groups.length
    assert dock.detach(:search)
    assert_equal ["search"], detached
    assert_equal 3, changes.length
    assert_equal dock.layout.to_h, Zaniah::UI::DockLayout.from_h(dock.layout.to_h).to_h
    assert dock.split(:editor, target: dock.layout.find_panel(:search).id, side: :left)
    assert_equal 3, dock.layout.groups.length
    @window.render(dock, present: false)
    assert_equal :group, @window.accessibility_tree.root.role
  end

  def test_dock_keyboard_moves_tabs
    dock = Zaniah::UI::DockWorkspace.new(layout, render: ->(id) { Zaniah::UI::Label.new(id) })
    @window.render(dock, present: false)
    assert_equal :next_option, Zaniah::Input::Keymap.default_ui.dispatch("right", context: {in_dock: true})
    assert dock.send(:dock_action, "left", :next_option)
    assert_equal "search", dock.layout.find_group(:left).active
    assert dock.send(:dock_action, "left", :move_next)
    assert_equal "right", dock.layout.find_panel(:search).id
  end

  def test_dock_pointer_drag_moves_tab_between_groups
    dock = Zaniah::UI::DockWorkspace.new(layout, render: ->(id) { Zaniah::UI::Label.new(id) }).w(600).h(300)
    @window.render(dock, present: false)
    @window.input(Zaniah::Input::MouseDown.new(Zaniah::Point.new(40, 20), :left, [], 1))
    @window.input(Zaniah::Input::MouseMove.new(Zaniah::Point.new(500, 300), []))
    @window.input(Zaniah::Input::MouseUp.new(Zaniah::Point.new(500, 300), :left, []))
    assert_equal "right", dock.layout.find_panel(:files).id
  end

  def test_dock_detach_accepts_single_argument_lambda
    ids = []
    dock = Zaniah::UI::DockWorkspace.new(layout, render: ->(id) { Zaniah::UI::Label.new(id) })
      .on_detach(&->(id) { ids << id })
    assert dock.detach(:files)
    assert_equal ["files"], ids
  end

  def test_property_grid_controls_validation_virtualization_and_semantics
    schema = [{key: :title, label: "Title", type: :text,
      validation: Zaniah::UI::Validation.new.required},
      {key: :count, type: :number, validation: Zaniah::UI::Validation.new.number(min: 0)},
      {key: :enabled, type: :boolean}, {key: :tone, type: :select, options: %w[Warm Cool]}]
    schema.concat((0...300).map { |index| {key: "extra_#{index}"} })
    changes = []
    grid = Zaniah::UI::PropertyGrid.new(schema, {title: "Hello", count: 3, enabled: true}, height: 160)
      .on_change { |key, value, *_| changes << [key, value] }
    @window.render(grid, present: false)
    assert_equal :table, @window.accessibility_tree.root.role
    assert_operator @window.accessibility_tree.root.children.length, :<, 20
    assert_includes grid.tui_cells, "Title: Hello"
    refute grid.set(:title, "")
    assert_equal "Hello", grid.values[:title]
    assert_equal ["is required"], grid.errors[:title]
    invalid_cell = grid.accessibility_node(nil).children.first.children.last
    assert_equal "", invalid_cell.value
    assert_equal "is required", invalid_cell.children.last.label
    assert grid.set(:title, "World")
    assert grid.set(:count, 4)
    assert_equal [[:title, "World"], [:count, 4]], changes
    @window.render(grid, present: false)
    assert_equal false, @window.accessibility_tree.root.children.first.states[:invalid]
    assert_operator grid.instance_variable_get(:@list).visible_range.size, :<, 20
  end

  private

  def walk_roles(node)
    [node.role, *node.children.flat_map { |child| walk_roles(child) }]
  end
end
