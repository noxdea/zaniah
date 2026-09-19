# Declarative elements

`Zaniah::Describe` rebuilds element trees from plain data. The application owns
the vocabulary, so it decides which node types and properties untrusted or
remote producers may use.

```ruby
vocabulary = Zaniah::Describe::Vocabulary.build do
  node :column, props: {gap: :integer} do |props, children|
    Zaniah::Div.new.flex_col.gap(props.fetch(:gap)).children(children)
  end

  node :button,
    props: {label: :string, on_click: :handler}, children: :none do |props|
    Zaniah::UI::Button.new(props.fetch(:label)).on_click(&props.fetch(:on_click))
  end
end

tree = {
  "type" => "column",
  "props" => {"gap" => 8},
  "children" => [{
    "type" => "button",
    "props" => {"label" => "Save", "on_click" => ["save", 1]},
    "children" => [],
    "key" => "save"
  }]
}

surface = Zaniah::Describe::Surface.new(
  vocabulary: vocabulary,
  on_event: ->(id, payload) { send_event(id, payload) }
)
surface.replace(tree)
window.draw { surface.element }
```

Property validators include `:string`, `:integer`, `:number`, `:boolean`,
`:array`, `:hash`, `:symbol`, `:handler`, `:any`, classes, callables, and arrays
of allowed values. Children may be `:none`, `:one`, `:many`, an exact count,
or a range. JSON string keys are normalized to symbols, and string values are
normalized for symbol enums.

Handler properties contain an opaque string or array ID. The factory receives
a callable in its place; invoking it sends the ID and the first payload argument
to `on_event`.

`Zaniah::Describe.diff(previous, current)` returns `Patch` records with
`:replace`, `:insert`, `:remove`, or `:update` operations. Paths are arrays of
child indexes from the root, and `:update` contains the complete new property
map. `Surface#apply` validates and applies a patch set atomically. Its `element`
reader performs no building or I/O, and unchanged keyed subtrees retain their
element instances across reordering.
