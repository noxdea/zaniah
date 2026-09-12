# Components

The optional component layer is loaded with `require "zaniah/ui"`. Components use the
same `request_layout` / `prepaint` / `paint` protocol as elements and may be placed
directly in an element tree. Builder methods return the component.

```ruby
require "zaniah/ui"

save = Zaniah::UI::Button.new("Save", variant: :primary, size: :md)
  .icon(:check)
  .on_click { |_event, cx| cx.window.request_frame }
```

Applications may extend variant tables:

```ruby
Zaniah::UI::Button.variants[:variant][:brand] = ->(theme) {
  {background: theme.colors.success, hover: theme.colors.success,
   foreground: theme.colors.text_inverse, border: theme.colors.success}
}
```

## Component reference

| Layer | Component | Main constructor/options | Variants | Accessibility role |
| --- | --- | --- | --- | --- |
| L0 | `Label` | `(text, tone:, size:, wrap:)` | tone: default/muted/inverse; size: xs–xl | text |
| L0 | `Icon` | `(source, size:, color:, label:)` | bundled: check/close/search/menu/info/warning | image when labeled |
| L0 | `Divider` | `(axis:)` | horizontal/vertical | separator |
| L0 | `Spacer` | `(size = nil)` | fixed or flexible | none |
| L0 | `Card` | `(*children)`, `child` | theme surface | group |
| L0 | `Badge` | `(text, variant:)` | neutral/accent/success/warning/danger | text |
| L0 | `Avatar` | `(name, image:, size:)` | initials or PNG | image |
| L0 | `Skeleton` | `(width:, height:)` | pulsing loading placeholder | progressbar/busy |
| L0 | `EmptyState` | `(title, message:, icon:, action:)` | compositional | group |
| L1 | `Button` | `(label, size:, variant:)`; `disabled`, `loading`, `icon`, `on_click` | sm/md/lg × primary/secondary/ghost/danger | button |
| L1 | `IconButton` | `(icon, label:, ...)` | Button variants | button |
| L1 | `ToggleButton` | `(label, value:)`; `on_change` | Button variants | button/pressed |
| L1 | `ButtonGroup` | `(*buttons)`, `child` | horizontal | group |
| L1 | `Checkbox` | `(label, value:, disabled:)`; `on_change` | true/false/mixed | checkbox |
| L1 | `Radio` | `(label, value:, disabled:)`; `on_change` | selected/unselected | radio |
| L1 | `RadioGroup` | `(options, value:)`; `on_change` | one selected value | radiogroup |
| L1 | `Switch` | `(label, value:, disabled:)`; `on_change` | on/off | switch |
| L1 | `Slider` | `(value:, min:, max:, step:, label:)`; `on_change` | pointer + arrow/Home/End/Page keys | slider |
| L1 | `RangeSlider` | `(value: [low, high], ...)` | two thumbs | slider |
| L1 | `ProgressBar` | `(value:, min:, max:, label:)` | determinate/indeterminate | progressbar |
| L1 | `Spinner` | `(label:, size:)` | animated loading indicator | progressbar/busy |
| L1 | `Meter` | `(value:, low:, high:, optimum:)` | thresholds | meter |
| L2 | `Tooltip` | `(text, anchor:, side:, open:)` | top/bottom/left/right | tooltip |
| L2 | `Popover` | `(content, anchor:, side:, width:, height:, open:, modal:)` | flipped and viewport-clamped | group |
| L2 | `ContextMenu`, `Menu` | `(items, anchor:, open:)` | pointer + arrows/Home/End/Enter/Esc | menu/menuitem |
| L2 | `MenuBar` | `(menus)` | compositional | menubar |
| L2 | `Dropdown` | `(label, items:, value:)`; `on_change` | menu-backed | button |
| L2 | `TextField` | `(value, placeholder:, label:, prefix:, suffix:, error:, max_length:, clearable:)` | IME, selection, counter | textbox |
| L2 | `TextArea` | TextField plus `rows:` | multiline/wrapped | textbox/multiline |
| L2 | `SearchInput` | TextField options | search + clear icons | searchbox |
| L2 | `PasswordInput` | TextField options | masked display | textbox |
| L2 | `NumberInput` | TextField plus `min:`, `max:`, `step:`; `increment`, `decrement` | numeric | textbox |
| L2 | `TagInput` | `(tags, separator:, ...)`; `on_tags_change` | badge list + editor | textbox |
| L3 | `Tabs` | `(items, selected:)`; `on_change` | arrows/Home/End | tab/tabpanel |
| L3 | `Accordion` | `(items, multiple:, open:)` | single/multiple | group |
| L3 | `Collapsible` | `(label, content, open:)`; `on_change` | open/closed | button/expanded |
| L3 | `Breadcrumb` | `(items)` | labels or label/callback pairs | navigation/link |
| L3 | `Pagination` | `(page:, pages:, window:)`; `on_change` | previous/window/next | navigation |
| L3 | `Toolbar` | `(*children)`, `child` | horizontal | toolbar |
| L3 | `StatusBar` | `(*children)`, `child` | horizontal | status |
| L3 | `Sidebar` | `(*children, width:)`, `child` | vertical | navigation |
| L3 | `Modal`, `Dialog` | `(content, title:, open:, close_on_scrim:, width:)` | focus trap, scrim, Esc | dialog/modal |
| L3 | `Drawer` | Modal plus `side:` | left/right | dialog/modal |
| L3 | `Toast` | `(message, variant:, queue:)`; `dismiss` | info/success/warning/danger | live status |
| L3 | `CommandPalette` | `(commands, open:, placeholder:)` | searchable modal | dialog/list |
| L4 | `Table`, `DataGrid` | `(rows, columns:, height:, selection:, row_key:)`; `on_sort`, `on_select`, `on_edit` | virtual rows, sorting, resizing, editing | table/row/cell |
| L4 | `TreeView` | `(items, height:, selected:)`; `expand`, `collapse`, lazy `children` proc | arrows/Home/End | tree/treeitem |
| L5 | `Sparkline` | `(values, width:, height:, color:, label:)` | line + tooltip | image |
| L5 | `LineChart`, `BarChart` | `(series, width:, height:, colors:, label:)` | axes, legend, tooltip | image |
| L5 | `Validation` | `required`, `format`, `length`, `number`, `rule` | composable rules | n/a |
| L5 | `FormField` | `(name, value:, label:, control:, validation:, hint:)` | errors + describedby | group/control/alert |
| L5 | `Form` | `field`, `on_change`, `on_submit`, `values`, `valid?` | validates before submit | form |

All input components are keyboard operable. Disabled controls remain visible but are
removed from focus traversal. Overlay components close on Esc; modal overlays restore
the previous focus. See [TUI](tui.md) for terminal representations.

Table columns are hashes with `key`, and optional `label`, `width`, `sortable`,
`resizable`, `editable`, and `render`. Tree items accept hashes containing `id`,
`label`, and either an array or lazy proc in `children`.

In a table, Up/Down/Home/End/Page keys move and select rows, Shift+Up/Down extends
a range, and Cmd/Ctrl+A selects every row in multiple-selection mode. Sortable
headers and resize handles are separate Tab stops; Enter sorts and arrow/Page keys
resize. Tree views use Up/Down to select and Left/Right to collapse or expand.

Run `bundle exec ruby tools/generate_component_gallery.rb` to rebuild the dark,
light, and high-contrast component sheets plus the two-theme overlay variants.
