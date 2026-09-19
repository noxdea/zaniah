# frozen_string_literal: true

require_relative "test_helper"

class DescribeTest < Minitest::Test
  D = Zaniah::Describe

  def setup
    @events = []
    @vocabulary = D::Vocabulary.build do
      node :column, props: {gap: :integer}, children: :many do |props, children|
        Zaniah::Div.new.style(**props).children(children)
      end
      node :text, props: {value: :string, tone: %i[normal dim]}, children: :none do |props|
        Zaniah::Text.new(props.fetch(:value))
      end
      node :button, props: {label: :string, on_click: :handler}, children: :none do |props|
        Zaniah::Div.new.test_id(props.fetch(:label)).on_click(&props.fetch(:on_click))
      end
    end
  end

  def test_vocabulary_validates_types_properties_children_and_keys
    node = json_node("text", {"value" => "hello", "tone" => "dim"})
    assert_equal :text, @vocabulary.validate!(node).type
    assert @vocabulary.allow?("text")
    refute @vocabulary.allow?(:missing)

    assert_raises(ArgumentError) { @vocabulary.validate!(json_node("missing")) }
    assert_raises(ArgumentError) { @vocabulary.validate!(json_node("text", {"value" => 1})) }
    assert_raises(ArgumentError) { @vocabulary.validate!(json_node("text", {"value" => "x", "extra" => true})) }
    assert_raises(ArgumentError) do
      @vocabulary.validate!(json_node("text", {"value" => "x"}, [json_node("text", {"value" => "child"})]))
    end
    assert_raises(ArgumentError) do
      @vocabulary.validate!(json_node("column", {}, [text_node("a", key: "same"), text_node("b", key: "same")]))
    end
  end

  def test_build_creates_elements_and_routes_handler_ids
    tree = json_node("column", {"gap" => 4}, [
      json_node("text", {"value" => "hello"}),
      json_node("button", {"label" => "Save", "on_click" => ["save", 7]}, key: "save")
    ])

    element = D.build(tree, vocabulary: @vocabulary, on_event: ->(id, payload) { @events << [id, payload] })
    assert_instance_of Zaniah::Div, element
    assert_equal "hello", element.children.first.text
    button = element.children.last
    assert_equal "save", button.identity_key
    payload = {"source" => "pointer"}
    button.instance_variable_get(:@handlers).fetch(:click).call(payload)
    assert_equal [[["save", 7], payload]], @events
  end

  def test_diff_updates_properties_without_replacing_the_node
    before = column(text_node("before", key: "label"))
    after = column(text_node("after", key: "label"))

    patches = D.diff(before, after)
    assert_equal [:update], patches.map(&:op)
    assert_equal [0], patches.first.path
    assert_equal({value: "after", tone: :normal}, patches.first.props)
  end

  def test_diff_uses_insert_and_remove_for_keyed_reordering
    before = column(text_node("A", key: "a"), text_node("B", key: "b"))
    after = column(text_node("B", key: "b"), text_node("A", key: "a"))

    patches = D.diff(before, after)
    assert_equal %i[remove insert], patches.map(&:op)
    refute_includes patches.map(&:op), :replace
  end

  def test_surface_applies_patches_and_reuses_keyed_elements
    before = column(text_node("A", key: "a"), text_node("B", key: "b"))
    after = column(text_node("B", key: "b"), text_node("A", key: "a"))
    surface = D::Surface.new(vocabulary: @vocabulary, on_event: ->(*) {})

    assert surface.empty?
    assert_nil surface.element
    surface.replace(before)
    first_a, first_b = surface.element.children
    surface.apply(D.diff(before, after))

    refute surface.empty?
    second_b, second_a = surface.element.children
    assert_same first_a, second_a
    assert_same first_b, second_b
  end

  def test_surface_validation_is_transactional
    before = column(text_node("A", key: "a"))
    surface = D::Surface.new(vocabulary: @vocabulary, on_event: ->(*) {}).replace(before)
    element = surface.element
    invalid = D::Patch.new(:update, [0], nil, {value: 3})

    assert_raises(ArgumentError) { surface.apply([invalid]) }
    assert_same element, surface.element
  end

  def test_diff_handles_empty_and_replaced_roots
    text = text_node("A")
    button = D::Node.new(:button, {label: "Run", on_click: "run"}, [], nil)
    surface = D::Surface.new(vocabulary: @vocabulary, on_event: ->(*) {})

    assert_equal [:insert], D.diff(nil, text).map(&:op)
    surface.apply(D.diff(nil, text))
    assert_instance_of Zaniah::Text, surface.element
    assert_equal [:replace], D.diff(text, button).map(&:op)
    surface.apply(D.diff(text, button))
    assert_instance_of Zaniah::Div, surface.element
    assert_equal [:remove], D.diff(button, nil).map(&:op)
    surface.apply(D.diff(button, nil))
    assert surface.empty?
  end

  private

  def json_node(type, props = {}, children = [], key: nil)
    {"type" => type, "props" => props, "children" => children, "key" => key}
  end

  def text_node(value, key: nil)
    D::Node.new(:text, {value: value, tone: :normal}, [], key)
  end

  def column(*children)
    D::Node.new(:column, {gap: 1}, children, nil)
  end
end
