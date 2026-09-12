# frozen_string_literal: true

require "fileutils"
require "alhena"
require_relative "../examples/gallery"

OUTPUT = File.expand_path(ARGV.find { |argument| !argument.start_with?("--") } || "../docs/gallery", __dir__)
SHEETS = %i[dark light high_contrast].freeze
OVERLAYS = %w[
  tooltip-top tooltip-bottom tooltip-left tooltip-right
  popover-top popover-bottom popover-left popover-right
  menu context-menu modal dialog drawer-left drawer-right
  toast-info toast-success toast-warning toast-danger command-palette
].freeze
FONT = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))

FileUtils.mkdir_p(OUTPUT)

SHEETS.each do |appearance|
  app = Zaniah::App.new(clock: -> { 0.0 })
  window = app.open_window(width: 900, height: 1840)
  theme = Zaniah::Theme.public_send(appearance)
  app.global(:theme, theme.with(motion: theme.motion.with(reduced: true)))
  window.text_system = Zaniah::TextSystem::Renderer.new(font: FONT, font_db: Zaniah::TextSystem::FontDB.new(paths: []))
  unless ARGV.include?("--overlays-only")
    window.draw { Gallery.page }
    window.tick
    window.write_png(File.join(OUTPUT, "components-#{appearance}.png"))
  end

  OVERLAYS.each do |name|
    next if ARGV.include?("--sheets-only")
    next if appearance == :high_contrast
    window.resize(900, 700)
    window.draw do
      Zaniah::Div.new.w_full.h_full.bg(theme.colors.background)
        .child(Zaniah::Anchored.new(anchor: Zaniah::Point.new(24, 24))
          .child(Zaniah::UI::Label.new("#{name.tr("-", " ").capitalize} preview", size: :xl)))
        .child(Gallery.overlay(name, window))
    end
    window.tick
    window.write_png(File.join(OUTPUT, "#{name}-#{appearance}.png"))
  end
  window.close
  app.executor.shutdown
end

count = (ARGV.include?("--overlays-only") ? 0 : SHEETS.length) + (ARGV.include?("--sheets-only") ? 0 : OVERLAYS.length * 2)
puts "gallery: wrote #{count} PNG files to #{OUTPUT}"
