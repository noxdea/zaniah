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
| L0 | `Kbd` | `(keys, platform:)`; `.for(action, keymap:)` | OS shortcut notation, including multi-stroke bindings | text |
| L0 | `Alert` | `(title, message:, variant:, action:, dismissible:, live:)`; `dismiss` | info/success/warning/danger; persistent until dismissed | alert when live, otherwise status |
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
| L1 | `SegmentedControl` | `(options, value:)`; `on_change` | mutually exclusive segments; arrows/Home/End | radiogroup/radio |
| L1 | `Switch` | `(label, value:, disabled:)`; `on_change` | on/off | switch |
| L1 | `Slider` | `(value:, min:, max:, step:, label:)`; `on_change` | pointer + arrow/Home/End/Page keys | slider |
| L1 | `RangeSlider` | `(value: [low, high], ...)` | two thumbs | slider |
| L1 | `ProgressBar` | `(value:, min:, max:, label:)` | determinate/indeterminate | progressbar |
| L1 | `Spinner` | `(label:, size:)` | animated loading indicator | progressbar/busy |
| L1 | `Meter` | `(value:, low:, high:, optimum:)` | thresholds | meter |
| L2 | `Tooltip` | `(text, anchor:, side:, open:)` | top/bottom/left/right | tooltip |
| L2 | `Popover` | `(content, anchor:, side:, width:, height:, open:, modal:)` | flipped and viewport-clamped | group |
| L2 | `HoverCard` | `(content, anchor:, open_delay:, close_delay:)` | hover or focus opens after a delay; non-modal | dialog |
| L2 | `ContextMenu`, `Menu` | `(items, anchor:, open:)` | pointer + arrows/Home/End/Enter/Esc | menu/menuitem |
| L2 | `MenuBar` | `(menus)` or `.from(app.menu_bar)` | declarative menu model or legacy pairs | menubar |
| L2 | `Dropdown` | `(label, items:, value:)`; `on_change` | menu-backed | button |
| L2 | `TextField` | `(value, placeholder:, label:, prefix:, suffix:, error:, max_length:, clearable:)` | IME, selection, counter | textbox |
| L2 | `TextArea` | TextField plus `rows:` | multiline/wrapped | textbox/multiline |
| L2 | `SearchInput` | TextField options | search + clear icons | searchbox |
| L2 | `PasswordInput` | TextField options | masked display | textbox |
| L2 | `NumberInput` | TextField plus `min:`, `max:`, `step:`; `increment`, `decrement` | numeric | textbox |
| L2 | `TagInput` | `(tags, separator:, ...)`; `on_tags_change` | badge list + editor | textbox |
| L2 | `Select` | `(items, label:, value:, disabled:)`; `on_change` | single choice | combobox |
| L2 | `Combobox` | `(items, value:, label:, placeholder:, disabled:, matcher:)`; `on_change` | editable, filtered choices with highlighted matches | combobox |
| L2 | `MultiSelect` | `(items, value:, label:, disabled:)`; `on_change` | multiple selected badges | listbox |
| L2 | `DatePicker` | `(value, min:, max:, label:, disabled:)`; `on_change` | ISO date, day/week keyboard steps | combobox |
| L2 | `Calendar` | `(value:, min:, max:, range:, week_start:, month_names:)`; `on_change` | arrow keys move days/weeks, Page keys move months, Enter selects | grid/gridcell |
| L2 | `DateRangePicker` | `(value:, min:, max:, week_start:, month_names:)`; `on_change` | Calendar-backed start/end selection | combobox |
| L2 | `TimePicker` | `(value, step:, label:, disabled:)`; `on_change` | 24-hour time, minute/hour keyboard steps | combobox |
| L2 | `ColorPicker` | `(value, label:, swatches:, disabled:)`; `on_change` | hex input and swatches | combobox |
| L3 | `Tabs` | `(items, selected:)`; `on_change` | arrows/Home/End | tab/tabpanel |
| L3 | `ScrollView` | `(axis:, scrollbar:)`; `scroll_to` | vertical/horizontal/both; overlay/always/hidden | child tree |
| L3 | `Scrollbar` | `(scroll_state, axis:, mode:)` | drag, track paging, arrows/Home/End/Page keys | scrollbar |
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
| L3 | `CommandPalette` | `(commands, open:, placeholder:, matcher:)`; `.from(app.actions)` | searchable modal, Up/Down/Enter | dialog/list |
| L3 | `SplitPane` | `(first, second, orientation:, ratio:, min:, max:)`; `on_change` | horizontal/vertical, draggable separator | group/separator |
| L3 | `PaneGrid` | `(panes, columns:, rows:, divider_size:, minimum:, keyboard_step:)`; `replace`, `on_resize` | arbitrary resizable grid, stable pane IDs | group/separator |
| L3 | `Resizable` | `(content, width:, height:, min_width:, min_height:, max_width:, max_height:)`; `on_resize` | drag or keyboard resize | group/separator |
| L3 | `ZoomPanView` | `(content, zoom:, min_zoom:, max_zoom:)`; `fit`, `zoom_to`, `view_to_content` | drag to pan, pinch or Ctrl+wheel to zoom, `+`/`-`/`0` when focused | group |
| L3 | `DockPanel` | `(center:, top:, right:, bottom:, left:)` | five-region layout | group |
| L3 | `DockWorkspace` | `(layout, render:)`; `on_layout_change`, `on_detach`; `DockLayout.to_h`/`.from_h` | drag tabs to move/split, arrows select, Alt+arrows move, Ctrl+Shift+arrows split, Ctrl+Shift+D requests detach | tablist/tab/tabpanel/separator |
| L3 | `ListView` | `(items, height:, row_height:, selected:)`; `on_select` | virtual rows and keyboard selection | list/listitem |
| L4 | `Table`, `DataGrid` | `(rows, columns:, height:, selection:, row_key:)`; `on_sort`, `on_select`, `on_edit`, `on_copy`, `on_paste` | virtual rows, sorting, resizing, editing, typed clipboard hooks | table/row/cell |
| L4 | `Grid` | `(rows:, columns:, row_height:, column_width:, frozen_rows:, frozen_columns:)`; `scroll_to`, range `selection`, `on_select`, `on_edit`, `on_fill`, `on_resize`, `on_copy`, `on_paste` | two-axis virtualization, frozen panes, visible-cell resize/fill and typed clipboard hooks | table |
| L4 | `TreeView` | `(items, height:, selected:)`; `expand`, `collapse`, `replace`, `replace_children`, `invalidate`, lazy `children` proc | arrows/Home/End | tree/treeitem |
| L4 | `PropertyGrid` | `(schema, values, height:, row_height:)`; `on_change`, `set` | typed existing controls, `Validation`, virtual rows | table/row/cell |
| L5 | `Sparkline` | `(values, width:, height:, color:, label:)` | line + tooltip | image |
| L5 | `LineChart`, `BarChart`, `StackedBarChart`, `AreaChart` | `(series, width:, height:, colors:, label:)`; `AreaChart(stacked:)` | shared axes, ticks, grid lines, color-keyed legend, tooltip | image |
| L5 | `PieChart`, `DonutChart` | `(data, width:, height:, colors:, label:)` | slices, shared color-keyed legend, tooltip | image |
| L5 | `ScatterChart` | `(series, width:, height:, colors:, label:)` | shared axes, ticks, grid lines, color-keyed legend, nearest-point tooltip | image |
| L5 | `Validation` | `required`, `format`, `length`, `number`, `rule` | composable rules | n/a |
| L5 | `FormField` | `(name, value:, label:, control:, validation:, hint:)` | errors + describedby | group/control/alert |
| L5 | `Form` | `field`, `on_change`, `on_submit`, `values`, `valid?` | validates before submit | form |
| L5 | `CodeEditor` | `(value, buffer:, highlighter:, wrap:, language:, line_numbers:, read_only:)`; `on_change` | viewport-only multiline editor with syntax scopes and Tab indentation | textbox |
| L5 | `RichText` | `(runs, selectable:, editable:, writing_mode:, text_orientation:)`; `apply`, `insert`, `delete`, `replace`, `append`, `insert_embed`, `paragraph_style` | styled editing, inline embeds, ruby, vertical text, IME, range selection and caret | text/textbox |

All input components are keyboard operable. Disabled controls remain visible but are
removed from focus traversal. Overlay components close on Esc; modal overlays restore
the previous focus. See [TUI](tui.md) for terminal representations.

`Calendar` and `DateRangePicker` use Ruby's `Date` and ISO 8601 strings. Pass
`week_start: 0..6` (Sunday is 0) and twelve `month_names:` to localize the grid
without an i18n dependency. A range picker returns a two-element array of dates;
its second value is `nil` while the user is choosing the end. `HoverCard` accepts
an element/component as its anchor to open on pointer hover or keyboard focus, or
a `Point`/`Bounds` for positioned use. Its delays follow the window's injected clock.

`ZoomPanView` uses content-local coordinates for `zoom_to` and `view_to_content`.
Call `fit` after the first layout; it scales the content into the current viewport.
Native macOS pinch emits `Input::Magnify`, while Ctrl+wheel provides a desktop fallback.

`DockLayout` is a validated tree of tab groups and horizontal/vertical splits with
stable string IDs. Use `DockLayout.tabs` and `.split` to build it, and persist
`layout.to_h` in the application; `DockLayout.from_h` restores it. `DockWorkspace`
passes the active panel ID to `render:` and emits a new layout on tab changes.
`on_detach` is a notification only; the application decides whether to open a
window and remove the panel. A pointer drop in the outer 20% of a group splits it.
`PropertyGrid` schema entries use `key`, optional `label`, `type` (`text`,
`textarea`, `number`, `boolean`, `select`, `color`, `date`, `time`), `options` for
select, and an optional `Validation`. Invalid edits remain in the control while
the last valid value is retained. Both components expose terminal fallbacks.

`Combobox` and `CommandPalette` default to case-insensitive substring matching in
input order. Pass `matcher:` to either component, or set a default with
`Zaniah.configure { |config| config.matcher = matcher }`. A matcher implements
`match(query, labels)` and returns `UI::Matcher::Match` values with an original
label `index`, descending `score`, and half-open UTF-8 byte `ranges` for highlighting.
It may also implement `refine(previous_matches, query)` for incremental queries.
`CommandPalette.from(app.actions)` uses registered action titles, disables
unavailable actions, and displays shortcuts with `UI::Kbd`. See [Menus](menus.md).

`UI::RichText` accepts UTF-8 byte ranges at grapheme boundaries. Inline styles are
`bold`, `italic`, `size`, `color`, `font`, `link`, `underline` (`:single`, `:double`,
`:wavy`), `underline_color`, `strikethrough`, `background`, `baseline`
(`:superscript` or `:subscript`), `letter_spacing`, `ruby: "reading"`, and
`combine_upright: true`. Ruby parent text is one unbreakable selection cluster;
copying omits the annotation, while accessibility and TUI expose it in
parentheses. Ruby and combine-upright cannot be set together on one run.
`writing_mode: :vertical_rl` uses top-to-bottom lines and right-to-left columns;
`text_orientation: :mixed` rotates ordinary Latin by default, whereas `:upright`
keeps it upright. Paragraph styles include
alignment, lists, levels, `indent`, `quote`, `background`, and before/after spacing.
`insert_embed(offset, key:, width:, height:) { |cx| element }` stores U+FFFC in the
text and lays the element out at that inline position. `append(text, style:)` reuses
cached layouts for unchanged earlier fragments. RichText is read-only by default;
set `editable: true` to enable keyboard editing and IME.

`UI::CodeEditor` keeps the legacy positional constructor and also accepts a
line-addressable `buffer:` with `line_count`, `line(index)`, `line_start(index)`,
`line_of(offset)`, `replace(range, text)`, `undo`, and `redo`. A plain string or
`TextBuffer` uses the bundled adapter. Optional `highlighter:` provides
`tokens(line_index, text)` byte ranges with scopes and receives
`edited(range, new_text)` notifications. Scopes use `theme.syntax` colors. Only
visible logical lines are shaped; wrapped display rows share one line number.
The editor supports one caret/selection, standard text actions, IME placement,
and Tab indentation. See [ADR 020](adr/020-lightweight-code-editor-providers.md).

## Image decoding

`Image.from_bytes(bytes)` detects PNG, GIF, and baseline JPEG by signature. Pass
`format: :png`, `:gif`, or `:jpeg` to choose explicitly. JPEG supports 8-bit
baseline grayscale and three-component RGB/YCbCr, JFIF frame dimensions, Exif
orientation 1–8, and 4:4:4, 4:2:2, and 4:2:0 sampling. Progressive, CMYK,
arithmetic-coded, and multi-scan JPEG files raise `JPEG::Error`; the default
pixel limit is 16,777,216.

Table columns are hashes with `key`, and optional `label`, `width`, `sortable`,
`resizable`, `editable`, and `render`. Tree items accept hashes containing `id`,
`label`, and either an array or lazy proc in `children`. A lazy proc receives the
item value, runs on first expansion, and is cached after it succeeds; a raised
exception leaves it available for retry. A loader can return a placeholder while
work runs elsewhere; call `replace_children(id, children)` on the UI thread to
apply the result without changing selection, focus, or expansion. It returns
`false` when the ID is missing or is not lazy. `invalidate(id)` likewise returns
`false` for missing or non-lazy items; otherwise it discards that lazy result and
its loaded descendants so the next expansion calls the loader again. Omit the ID
to invalidate all loaded results. `replace(items)` starts a
new source generation, so it never inherits loaded children from the old source.
Completed children must be an array with unique, non-nil stable IDs, at most 64
levels deep and 100,000 items total. Invalid results leave the previous children
unchanged. Tree rows and accessibility nodes are built only for the current
viewport.

In a table, Up/Down/Home/End/Page keys move and select rows, Shift+Up/Down extends
a range, and Cmd/Ctrl+A selects every row in multiple-selection mode. Sortable
headers and resize handles are separate Tab stops; Enter sorts and arrow/Page keys
resize. Grid and Table clipboard hooks receive half-open `Grid::Area` ranges;
Table areas follow the current display order without changing its stable-ID
selection. See [Layout](layout.md#two-axis-virtual-grid). Tree views use Up/Down to select, Right to expand or enter the first child,
and Left to collapse or return to the parent.
