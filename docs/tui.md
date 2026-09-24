# TUI component degradation

`Platform.open_window(backend: :tui)` renders the ordinary element tree as terminal
cells. `Component#tui_cells` also exposes the deterministic fallback used by snapshot
tests and non-window integrations.

| Component family | Terminal representation |
| --- | --- |
| Label, Badge, Avatar | text, `[badge]`, `(initials)` |
| Kbd | textual shortcut, such as `Ctrl+Shift+P`; multiple strokes are space-separated |
| Alert | persistent `! title: message`; dismissed alerts disappear, live alerts announce through accessibility |
| Icon | Unicode check/close/search/menu/info/warning symbol; unlabeled unknown icons are omitted |
| Divider, Card | `─`/`│` and box-drawing characters |
| Skeleton, Spinner, ProgressBar, Meter | shade cells, `◌`, or a ten-cell progress track; animation jumps to its terminal state |
| Button, IconButton, ToggleButton | `[ label ]`; disabled uses `( label )` |
| Checkbox, Radio, Switch | `[x]`, `(o)`, `[on ]` |
| SegmentedControl | `[A\|(B)\|C]`, with the selected segment in parentheses; arrows move selection |
| Slider, RangeSlider | ten-cell track and numeric value/range |
| Text inputs | `[value]`; password values are masked and validation errors have `!` |
| Select, Combobox, MultiSelect | labeled brackets, filtered menu marker, or comma-separated selected values |
| DatePicker, TimePicker, ColorPicker | labeled ISO date, 24-hour time, or hex color in brackets |
| Calendar, DateRangePicker | month grid with selected day in `[dd]`; picker shows `[start – end]`, with `…` for an unfinished range |
| Tooltip, Popover, Menu, MenuBar, Dropdown | status text or a box/menu with `>` selection marker; nested menus expose a Back row |
| HoverCard | content text while open; hidden while closed; focus uses the same open delay as hover |
| Tabs, Accordion, Collapsible | selected tab in brackets and `[+]`/`[-]` disclosure markers |
| ScrollView, Scrollbar | clipped child content and `│`/`─` track |
| Breadcrumb, Pagination, bars | slash-separated path, page status, space-separated content |
| Modal, Dialog, Drawer, CommandPalette | box-drawing overlay; palette filters results and supports Up/Down/Enter; focus stays inside until dismissed |
| SplitPane, PaneGrid, Resizable, DockPanel | `│`/`─` separators, resize corner, or ordered dock regions |
| ZoomPanView | zoom percentage and content text; focused `+`/`-`/`0` changes zoom, but pointer panning has no cell equivalent |
| DockWorkspace | active tab in parentheses inside `[tabs]`, split groups separated by `│` or `───`; arrows select, Alt+arrows move and Ctrl+Shift+arrows split without dragging |
| ListView | visible rows with `>` on the selected item |
| Toast | live status text |
| Table, DataGrid | header and visible rows separated with `|` |
| TreeView | indentation with `▸`/`▾` expansion markers |
| PropertyGrid | up to 20 `label: value` rows, with `!` and the validation message on errors; Up/Down/Page keys move the virtual row selection |
| Sparkline and all chart types | eight-level Unicode sparkline summary |
| Form, FormField | labeled values, `!` errors, and a submit button |
| CodeEditor | numbered logical lines; wrap, syntax colors, and inline IME underline degrade to plain cells |
| RichText | concatenated text runs; ruby readings appear in parentheses; inline embeds appear as U+FFFC and decoration/paragraph backgrounds and vertical geometry degrade to plain cells |

Rounded corners, shadows, gradients, and alpha scrims reduce to solid cells. Focus is
reported by the terminal cursor/reverse-video capability; motion introduced in M7 is
sampled at its final state. New components must document text, focus, disabled, and
overlay behavior in this table before release.
