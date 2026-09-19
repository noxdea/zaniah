# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "support/budget"

vocabulary = Zaniah::Describe::Vocabulary.build do
  node(:list) { |_props, children| Zaniah::Div.new.children(children) }
  node(:item, props: {value: :string}, children: :none) { |props| Zaniah::Text.new(props.fetch(:value)) }
end
items = Array.new(1_000) { |index| Zaniah::Describe::Node.new(:item, {value: index.to_s}, [], index) }
previous = Zaniah::Describe::Node.new(:list, {}, items, nil)
current = Zaniah::Describe::Node.new(:list, {}, [items.last, *items.take(999)], nil)
patches = Zaniah::Describe.diff(previous, current)
surface = nil

Bench.budget("apply a diff to 1000 described elements", 10.0,
  setup: -> { surface = Zaniah::Describe::Surface.new(vocabulary: vocabulary, on_event: ->(*) {}).replace(previous) }) do
  surface.apply(patches)
end
