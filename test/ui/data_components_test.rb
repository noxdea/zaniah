# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class DataComponentsTest < Minitest::Test
  T = Zaniah

  def setup
    @clock = T::TestClock.new
    @app = T::App.new(clock: @clock)
    @window = @app.open_window(width: 640, height: 480)
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def render(component)
    @window.draw { component }
    @window.request_frame
    @window.tick
    component
  end

  def test_table_sorts_selects_resizes_edits_and_virtualizes
    rows = Array.new(10_000) { |index| {id: index, name: "Row #{10_000 - index}"} }
    table = render(T::UI::DataGrid.new(rows,
      columns: [{key: :id, width: 80}, {key: :name, width: 140, editable: true}],
      height: 160, selection: :multiple, row_key: ->(row) { row[:id] }))

    assert_operator table.instance_variable_get(:@body).children.length, :<, 20
    table.sort_by(:id, direction: :desc)
    render(table)
    assert_equal 9_999, table.instance_variable_get(:@display_rows).first[:id]

    @window.input(T::Input::MouseDown.new(T::Point.new(20, 45), :left, [], 1))
    assert_includes table.selection, 9_999
    @window.input(T::Input::MouseDown.new(T::Point.new(100, 45), :left, [], 2))
    render(table)
    assert_equal [0, :name], table.instance_variable_get(:@editing)

    before = table.instance_variable_get(:@widths)[:id]
    @window.input(T::Input::MouseDown.new(T::Point.new(70, 10), :left, [], 1))
    @window.input(T::Input::MouseMove.new(T::Point.new(90, 10), []))
    @window.input(T::Input::MouseUp.new(T::Point.new(90, 10), :left, []))
    assert_operator table.instance_variable_get(:@widths)[:id], :>, before
    assert_equal :table, table.accessibility_node(nil).role
  end

  def test_tree_lazy_load_and_keyboard_navigation
    loads = 0
    tree = render(T::UI::TreeView.new([{id: :root, label: "Root", children: ->(_value) { loads += 1; [{id: :child, label: "Child"}] }}]))
    @window.dispatcher.focus(tree.focus_handle)
    @window.input(T::Input::KeyDown.new("right", false))
    render(tree)
    assert_equal 1, loads
    assert_includes tree.expanded, :root
    @window.input(T::Input::KeyDown.new("down", false))
    assert_equal :child, tree.selected_id
    assert_equal :tree, tree.accessibility_node(nil).role
  end

  def test_charts_emit_paths_tooltips_and_accessibility
    chart = render(T::UI::LineChart.new({Requests: [1, 3, 2], Errors: [0, 1, 0]}, width: 240, height: 120))
    assert_operator @window.scene.sprites.length, :>, 0
    assert_equal :image, chart.accessibility_node(nil).role
    assert_includes chart.tui_cells, "█"

    render(T::UI::BarChart.new([1, 2, 3], width: 240, height: 120))
    assert_operator @window.scene.sprites.length, :>, 0
  end

  def test_form_validation_and_describedby_relationship
    submitted = nil
    validation = T::UI::Validation.new.required.format(/@/, message: "must be an email")
    form = T::UI::Form.new.field(name: :email, value: "", validation: validation).on_submit { |values, *_| submitted = values }
    render(form)
    form.submit
    field = form.fields.first
    refute field.errors.empty?
    node = field.accessibility_node(nil)
    assert_equal true, node.children.first.states[:invalid]
    assert_equal field.error_id, node.children.first.states[:describedby]
    refute submitted
  end
end
