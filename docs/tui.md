# TUI component degradation

`Platform.open_window(backend: :tui)` renders the ordinary element tree as terminal
cells. `Component#tui_cells` also exposes the deterministic fallback used by snapshot
tests and non-window integrations.

| Component family | Terminal representation |
| --- | --- |
| Label, Badge, Avatar | text, `[badge]`, `(initials)` |
| Icon | Unicode check/close/search/menu/info/warning symbol; unlabeled unknown icons are omitted |
| Divider, Card | `─`/`│` and box-drawing characters |
| Skeleton, Spinner, ProgressBar, Meter | shade cells, `◌`, or a ten-cell progress track; animation jumps to its terminal state |
| Button, IconButton, ToggleButton | `[ label ]`; disabled uses `( label )` |
| Checkbox, Radio, Switch | `[x]`, `(o)`, `[on ]` |
| Slider, RangeSlider | ten-cell track and numeric value/range |
| Text inputs | `[value]`; password values are masked and validation errors have `!` |
| Tooltip, Popover, Menu, Dropdown | status text or a box/menu with `>` selection marker |
| Tabs, Accordion, Collapsible | selected tab in brackets and `[+]`/`[-]` disclosure markers |
| Breadcrumb, Pagination, bars | slash-separated path, page status, space-separated content |
| Modal, Dialog, Drawer, CommandPalette | box-drawing overlay; focus stays inside until dismissed |
| Toast | live status text |
| Table, DataGrid | header and visible rows separated with `|` |
| TreeView | indentation with `▸`/`▾` expansion markers |
| Sparkline, LineChart, BarChart | eight-level Unicode sparkline summary |
| Form, FormField | labeled values, `!` errors, and a submit button |

Rounded corners, shadows, gradients, and alpha scrims reduce to solid cells. Focus is
reported by the terminal cursor/reverse-video capability; motion introduced in M7 is
sampled at its final state. New components must document text, focus, disabled, and
overlay behavior in this table before release.
