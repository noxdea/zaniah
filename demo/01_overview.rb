# frozen_string_literal: true

require "fileutils"
require "zaniah"
require "wezen"

FileUtils.mkdir_p("docs/media")
window = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 360)
begin
  window.draw do
    Zaniah::Div.new.flex_col.gap(16).p(24).bg("#111827")
      .child(Zaniah::Div.new.w(280).h(42).bg("#2563eb").rounded(6))
      .child(Zaniah::Div.new.flex_row.gap(12)
        .child(Zaniah::Div.new.w(180).h(220).bg("#1f2937").rounded(6))
        .child(Zaniah::Div.new.w(380).h(220).bg("#0f172a").rounded(6)))
  end
  10.times { window.tick }
  png_path = "docs/media/overview.png"
  window.write_png(png_path)
  width, height, rgba = Zaniah::PNG.decode(File.binread(png_path))
  animation = Wezen::Animation.new(width: width, height: height).add(rgba, delay_ms: 1_000)
  Wezen::APNG.write("docs/media/overview.apng", animation)
ensure
  window&.close
end
