# frozen_string_literal: true

require "fileutils"
require "alhena"
require_relative "../examples/gallery"

OUTPUT = File.expand_path(ARGV.find { |argument| !argument.start_with?("--") } || "../docs/gallery", __dir__)
SHEETS = %i[dark light high_contrast].freeze
OVERLAYS = %w[
  tooltip-top tooltip-bottom tooltip-left tooltip-right
  popover-top popover-bottom popover-left popover-right
  hover-card
  menu context-menu modal dialog drawer-left drawer-right
  toast-info toast-success toast-warning toast-danger command-palette
].freeze
DOCS_OVERLAYS = %w[tooltip-bottom popover-right menu dialog drawer-right toast-success command-palette].freeze
FONT = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
docs_only = ARGV.include?("--docs-only")
sheets = docs_only ? [:dark] : SHEETS
overlays = docs_only ? DOCS_OVERLAYS : OVERLAYS
viewport_width = docs_only ? 700 : 900
overlay_height = docs_only ? 500 : 700

FileUtils.mkdir_p(OUTPUT)

sheets.each do |appearance|
  app = Zaniah::App.new(clock: -> { 0.0 })
  window = app.open_window(width: viewport_width, height: docs_only ? overlay_height : 3200,
    scale_factor: docs_only ? 2 : 1)
  theme = Zaniah::Theme.public_send(appearance)
  app.global(:theme, theme.with(motion: theme.motion.with(reduced: true)))
  window.text_system = Zaniah::TextSystem::Renderer.new(font: FONT, font_db: Zaniah::TextSystem::FontDB.new(paths: []))
  unless ARGV.include?("--overlays-only")
    window.draw { Gallery.page }
    window.tick
    window.write_png(File.join(OUTPUT, "components-#{appearance}.png"))
  end

  overlays.each do |name|
    next if ARGV.include?("--sheets-only")
    height = docs_only && %w[tooltip-bottom popover-right menu toast-success].include?(name) ? 260 : overlay_height
    window.resize(viewport_width, height)
    window.draw do
      frame = Zaniah::Div.new.w_full.h_full.bg(theme.colors.background)
      frame.child(Zaniah::Anchored.new(anchor: Zaniah::Point.new(24, 24))
        .child(Zaniah::UI::Label.new("#{name.tr("-", " ").capitalize} preview", size: :xl))) unless docs_only
      frame.child(Gallery.overlay(name, window))
    end
    window.tick
    window.write_png(File.join(OUTPUT, "#{name}-#{appearance}.png"))
  end
  window.close
  app.executor.shutdown
end

count = (ARGV.include?("--overlays-only") ? 0 : sheets.length) + (ARGV.include?("--sheets-only") ? 0 : overlays.length * sheets.length)
puts "gallery: wrote #{count} PNG files to #{OUTPUT}"
