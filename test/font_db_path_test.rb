# frozen_string_literal: true

require_relative "test_helper"

class FontDBPathTest < Minitest::Test
  def test_path_for_returns_only_fonts_opened_by_this_database
    path = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)
    db = Zaniah::TextSystem::FontDB.new(paths: [path])
    font = db.open(path)
    assert_equal path, db.path_for(font)
    assert_nil Zaniah::TextSystem::FontDB.new(paths: []).path_for(font)
    assert_nil db.path_for(Alhena::Font.open(path))
    db.refresh
    assert_nil db.path_for(font)
  end
end
