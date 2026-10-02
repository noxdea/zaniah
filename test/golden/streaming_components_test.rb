# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class StreamingComponentsGoldenTest < Zaniah::UITest
  Source = Struct.new(:count) do
    def cell(index, key) = key == :no ? index + 1 : "Log entry #{index + 1}"
    def row_id(index) = index
    def row_style(index) = index.odd? ? {background: "#345477", foreground: "#ffffff"} : nil
  end

  %i[dark light high_contrast].each do |appearance|
    define_method("test_streaming_components_#{appearance}") do
      theme = Zaniah::Theme.public_send(appearance)
      assert_golden("components/streaming-#{appearance}", theme: theme) do
        table = Zaniah::UI::VirtualTable.new(Source.new(100_000), columns: [{key: :no, label: "No.", width: 80, align: :end}, {key: :entry, label: "Message", width: 400}], height: 140)
        table.select(2)
        hex = Zaniah::UI::HexView.new("HTTP/1.1 200 OK\r\n\0" + (0..47).to_a.pack("C*"), height: 120).w(720)
        hex.highlights = [{range: 8...22, tone: :secondary}]
        hex.select(9...12)
        Zaniah::Div.new.w_full.h_full.p(20).gap(16).bg(theme.colors.background)
          .child(table).child(hex)
          .child(Zaniah::UI::TextField.new("tcp.port == 443", label: "Valid filter").status(:success))
          .child(Zaniah::UI::TextField.new("unknown", label: "Filter warning").status(:warning, message: "Unknown field"))
      end
    end
  end
end
