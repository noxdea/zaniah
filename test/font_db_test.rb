# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "alhena"

class FontDBTest < Minitest::Test
  DB = Zaniah::TextSystem::FontDB
  FONT_PATH = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)

  def tables(family, weight: 400, width: 5, style: :normal, codepoint: nil)
    font = Alhena::Font.open(FONT_PATH)
    result = font.tables.to_h { |tag, _| [tag, font.table(tag).data.dup] }
    entries = [[1, "Legacy Family"], [16, family], [21, "Localized Alias"]]
    encoded, records = "".b, "".b
    entries.each do |id, value|
      bytes = value.encode("UTF-16BE").b
      records << [3, 1, 0x409, id, bytes.bytesize, encoded.bytesize].pack("n6")
      encoded << bytes
    end
    result["name"] = [0, entries.length, 6 + records.bytesize].pack("n3") + records + encoded
    result["OS/2"][4, 4] = [weight, width].pack("n2")
    result["OS/2"][62, 2] = [style == :italic ? 1 : style == :oblique ? 512 : 0].pack("n")
    if codepoint
      mapping = [12, 0, 28, 0, 1, codepoint, codepoint, font.glyph_id("A")].pack("n2N6")
      result["cmap"] = [0, 1, 3, 10, 12].pack("n4N") + mapping
    end
    result
  end

  def sfnt(tables, offset: 0)
    position, directory, payload = offset + 12 + tables.length * 16, "".b, "".b
    tables.sort.each do |tag, bytes|
      directory << [tag, 0, position, bytes.bytesize].pack("a4N3")
      payload << bytes
      padding = -bytes.bytesize % 4
      payload << "\0" * padding
      position += bytes.bytesize + padding
    end
    [0x10000, tables.length, 0, 0, 0].pack("Nn4") + directory + payload
  end

  def collection(tables)
    position, offsets, data = 12 + tables.length * 4, [], "".b
    tables.each do |entry|
      offsets << position
      bytes = sfnt(entry, offset: position)
      data << bytes
      position += bytes.bytesize
    end
    "ttcf" + [0x10000, tables.length, *offsets].pack("N*") + data
  end

  def test_names_weights_width_and_style_come_from_metadata_not_filename
    Dir.mktmpdir("zaniah-fonts-") do |directory|
      variants = [["wrong-bold.ttf", 400, 5, :normal], ["unrelated.ttf", 700, 5, :normal], ["wide-name.ttf", 400, 3, :normal], ["upright-name.ttf", 400, 5, :italic]]
      paths = variants.map do |name, weight, width, style|
        path = File.join(directory, name)
        File.binwrite(path, sfnt(tables("Metadata Family", weight: weight, width: width, style: style)))
        path
      end
      db = DB.new(paths: paths.reverse)
      assert_equal 4, db.faces.length
      assert_equal 400, db.find(family: "metadata FAMILY").os2[:weight]
      assert_equal 700, db.find(family: "Metadata Family", weight: 650).os2[:weight]
      assert_equal 3, db.find(family: "Metadata Family", width: 4).os2[:width]
      assert_equal 1, db.find(family: "Metadata Family", style: :italic).table("OS/2").u16(62)
      assert_equal "Metadata Family", db.find(family: "Localized Alias").family
      assert_same db.find(family: "Metadata Family"), db.find(family: "Metadata Family")
    end
  end

  def test_css_400_to_500_preference_and_width_order
    Dir.mktmpdir("zaniah-font-order-") do |directory|
      paths = [300, 500, 600].map do |weight|
        path = File.join(directory, "#{weight}.ttf")
        File.binwrite(path, sfnt(tables("Weight Family", weight: weight)))
        path
      end
      db = DB.new(paths: paths)
      assert_equal 500, db.find(family: "Weight Family", weight: 400).os2[:weight]
      assert_equal 300, db.find(family: "Weight Family", weight: 350).os2[:weight]
      assert_equal 600, db.find(family: "Weight Family", weight: 550).os2[:weight]
    end
  end

  def test_every_ttc_face_is_discovered_and_used_for_fallback
    Dir.mktmpdir("zaniah-collection-") do |directory|
      path = File.join(directory, "misleading.ttc")
      File.binwrite(path, collection([tables("First", codepoint: 65), tables("第二", weight: 700, codepoint: 0x65e5)]))
      db = DB.new(paths: [path])
      assert_equal [0, 1], db.faces.map(&:index)
      assert_equal "第二", db.find(family: "第二", weight: 700).family
      primary = db.open(path)
      fallback = db.fallback(0x65e5, primary)
      assert_equal 1, fallback.index
      refute_equal 0, fallback.glyph_id(0x65e5)
      assert_same fallback, db.fallback(0x65e5, primary)
      assert_same primary, db.fallback(0x10ffff, primary)
      assert_equal 2, db.instance_variable_get(:@fonts).length
    end
  end

  def test_metadata_and_missing_character_probes_do_not_load_full_fonts
    db = DB.new(paths: [FONT_PATH])
    primary = Alhena::Font.open(FONT_PATH)
    File.stub(:binread, ->(*) { flunk "font blob loaded for metadata or absent glyph" }) do
      assert_equal "Abel", db.faces.first.family
      assert_same primary, db.fallback(0x10ffff, primary)
    end
    assert_empty db.instance_variable_get(:@fonts)
  end

  def test_invalid_metadata_and_requests_are_bounded
    Dir.mktmpdir("zaniah-invalid-fonts-") do |directory|
      path = File.join(directory, "broken.ttc")
      File.binwrite(path, "ttcf" + [0x10000, 0xffffffff].pack("N2"))
      db = DB.new(paths: [path, "missing.ttf"])
      assert_empty db.faces
      assert_equal "Abel", db.find.family
      assert_raises(ArgumentError) { db.find(weight: 0) }
      assert_raises(ArgumentError) { db.find(width: 10) }
      assert_raises(ArgumentError) { db.find(style: :unknown) }
      assert_raises(ArgumentError) { DB.new(paths: [nil]) }
      assert_same db, db.refresh
    end
  end
end
