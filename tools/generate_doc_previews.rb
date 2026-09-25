# frozen_string_literal: true

require "fileutils"
require "alhena"
require_relative "../examples/gallery"

OUTPUT = File.expand_path("../docs/previews", __dir__)
SECTIONS = {
  "foundation" => [0, 300, 700],
  "actions" => [1, 190, 730],
  "values" => [2, 180, 830],
  "text-input" => [3, 235, 600],
  "navigation" => [4, 190, 700],
  "structure" => [5, 340, 900],
  "variants" => [6, 440, 440],
  "data" => [7, 520, 900],
  "choices" => [8, 315, 600],
  "feedback" => [9, 570, 700],
  "workspace" => [10, 610, 900],
  "editors" => [11, 280, 750],
  "forms" => [12, 250, 450]
}.freeze

FileUtils.mkdir_p(OUTPUT)
font = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
app = Zaniah::App.new(clock: -> { 0.0 })
theme = Zaniah::Theme.dark
window = app.open_window(width: 900, height: 200, scale_factor: 2)
app.global(:theme, theme.with(motion: theme.motion.with(reduced: true)))
window.text_system = Zaniah::TextSystem::Renderer.new(font: font, font_db: Zaniah::TextSystem::FontDB.new(paths: []))

sections = Gallery.page.children
SECTIONS.each do |name, (index, height, width)|
  window.resize(width, height)
  section = sections.fetch(index).h(height - 32).p(24).gap(18)
  content = section.children.fetch(1)
  content.gap(20)
  content.children.first.gap(20) if content.children.length == 1 && content.children.first.is_a?(Zaniah::Div)
  content.children.first.children.last.h(110) if name == "foundation"
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
  window.resize(900, 345)
  card = Gallery.section(name == "grid" ? "Virtual grid" : "Pane grid",
    component, height: 313).p(24).gap(18)
  window.draw { Zaniah::Div.new.w_full.h_full.p(16).bg(theme.colors.background).child(card) }
  window.tick
  window.write_png(File.join(OUTPUT, "#{name}.png"))
end

window.close
app.executor.shutdown
puts "docs: wrote #{SECTIONS.length + extras.length} component previews to #{OUTPUT}"
