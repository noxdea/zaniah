# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "support/budget"

typesetter = Zaniah::TextSystem::Typesetter.new(font_db: Zaniah::TextSystem::FontDB.new(paths: []))
sample = ("Ruby שלום 123\n" * 1_000).chomp
Bench.budget("bidi paragraph 1000 lines", 16.67) do
  typesetter.layout_paragraph(sample, width: 320, wrap: :none, size: 14)
end
typesetter.close
