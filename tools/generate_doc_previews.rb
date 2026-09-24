# frozen_string_literal: true

require "fileutils"
require "alhena"
require_relative "../examples/gallery"

OUTPUT = File.expand_path("../docs/previews", __dir__)
SECTIONS = {
  "foundation" => [0, 200],
  "actions" => [1, 170],
  "values" => [2, 125],
  "text-input" => [3, 145],
  "navigation" => [4, 125],
  "structure" => [5, 270],
  "variants" => [6, 320],
  "data" => [7, 475],
  "choices" => [8, 245],
  "feedback" => [9, 445],
  "workspace" => [10, 565],
  "editors" => [11, 245],
  "forms" => [12, 185]
}.freeze

FileUtils.mkdir_p(OUTPUT)
font = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
app = Zaniah::App.new(clock: -> { 0.0 })
theme = Zaniah::Theme.light
window = app.open_window(width: 900, height: 200)
app.global(:theme, theme.with(motion: theme.motion.with(reduced: true)))
window.text_system = Zaniah::TextSystem::Renderer.new(font: font, font_db: Zaniah::TextSystem::FontDB.new(paths: []))

SECTIONS.each do |name, (index, height)|
  window.resize(900, height)
  section = Gallery.page.children.fetch(index)
  window.draw { Zaniah::Div.new.w_full.h_full.p(16).bg(theme.colors.background).child(section) }
  window.tick
  window.write_png(File.join(OUTPUT, "#{name}.png"))
end

extras = {
  "grid" => Zaniah::UI::Grid.new(rows: 30, columns: 10,
    row_height: 30, column_width: 110, frozen_rows: 1, frozen_columns: 1) do |row, column|
      row.zero? ? "Column #{column + 1}" : "R#{row} C#{column + 1}"
    end.w(840).h(210),
  "pane-grid" => Zaniah::UI::PaneGrid.new(
    [[[:files, Zaniah::UI::Label.new("Files")], [:editor, Zaniah::UI::Label.new("Editor")]]],
    columns: [Zaniah.fr(1), Zaniah.fr(2)], rows: [Zaniah.fr(1)]).w(840).h(210)
}
extras.each do |name, component|
  window.resize(900, 310)
  card = Gallery.section(name == "grid" ? "Virtual grid" : "Pane grid",
    component, height: 275)
  window.draw { Zaniah::Div.new.w_full.h_full.p(16).bg(theme.colors.background).child(card) }
  window.tick
  window.write_png(File.join(OUTPUT, "#{name}.png"))
end

window.close
app.executor.shutdown
puts "docs: wrote #{SECTIONS.length + extras.length} component previews to #{OUTPUT}"
