# frozen_string_literal: true

require "test_helper"
require "alhena"

class ShaperTest < Minitest::Test
  T = Zaniah::TextSystem
  class Font
    attr_reader :tables
    def initialize(**tables) = @tables = tables.transform_keys(&:to_s).transform_values { |value| Alhena::Binary.new(value) }
    def table(tag) = @tables.fetch(tag)
    def units_per_em = 1000
    def advance(_id, size:) = size.to_f
  end

  def u16(*values) = values.flatten.map { |v| v & 0xffff }.pack("n*")
  def patch(bytes, offset, value) = bytes[offset, 2] = u16(value)
  def coverage(*ids) = u16(1, ids.flatten.length, ids)
  def classes(mapping) = u16(2, mapping.length, mapping.sort.flat_map { |glyph, value| [glyph, glyph, value] })

  def tagged(records)
    body, header = "".b, u16(records.length)
    records.each do |tag, value|
      header << tag << u16(2 + records.length * 6 + body.bytesize)
      body << value
    end
    header + body
  end

  def script_table(languages, required = 0xffff)
    language = ->(indices) { u16(0, required, indices.length, indices) }
    defaults = languages[nil] && language.call(languages[nil])
    others = languages.reject { |tag, _| tag.nil? }
    header, body = u16(0, others.length), (defaults || "".b)
    patch(header, 0, 4 + others.length * 6) if defaults
    others.each do |tag, indices|
      header << tag << u16(4 + others.length * 6 + body.bytesize)
      body << language.call(indices)
    end
    header + body
  end

  def layout(lookups, features: {"liga" => [0]}, scripts: {"latn" => {nil => [0]}}, required: 0xffff)
    script_list = tagged(scripts.transform_values { |languages| script_table(languages, required) })
    feature_list = tagged(features.transform_values { |indices| u16(0, indices.length, indices) })
    lookup_list = u16(lookups.length)
    body = "".b
    lookups.each { |value| lookup_list << u16(2 + lookups.length * 2 + body.bytesize); body << value }
    u16(1, 0, 10, 10 + script_list.bytesize, 10 + script_list.bytesize + feature_list.bytesize) + script_list + feature_list + lookup_list + body
  end

  def lookup(type, *subtables, flags: 0, mark_set: 0)
    header_size = 6 + subtables.length * 2 + (flags & 16 != 0 ? 2 : 0)
    header, body = u16(type, flags, subtables.length), "".b
    subtables.each { |subtable| header << u16(header_size + body.bytesize); body << subtable }
    header << u16(mark_set) if flags & 16 != 0
    header + body
  end

  def single(mapping)
    ids = mapping.keys.sort
    u16(2, 6 + ids.length * 2, ids.length, ids.map { |id| mapping[id] }) + coverage(ids)
  end

  def ligature(input, output)
    set = u16(1, 4, output, input.length, input.drop(1))
    u16(1, 8 + set.bytesize, 1, 8) + set + coverage(input.first)
  end

  def chained(format, input:, back: [], ahead: [], actions:)
    if format == 3
      header, fixups = u16(3), []
      [back, input, ahead].each do |sequence|
        header << u16(sequence.length)
        sequence.each { |id| fixups << [header.bytesize, id]; header << u16(0) }
      end
      header << u16(actions.length, actions.flatten)
      fixups.each { |offset, id| patch(header, offset, header.bytesize); header << coverage(id) }
      return header
    end
    sequences = [back, input, ahead]
    if format == 2
      mappings = sequences.map { |sequence| sequence.uniq.each_with_index.to_h.transform_values { |index| index + 1 } }
      sequences = sequences.each_with_index.map { |sequence, i| sequence.map { |id| mappings[i].fetch(id) } }
    end
    b, i, a = sequences
    rule = u16(b.length, b, i.length, i.drop(1), a.length, a, actions.length, actions.flatten)
    set = u16(1, 4) + rule
    if format == 1
      u16(1, 8 + set.bytesize, 1, 8) + set + coverage(input.first)
    else
      header = u16(2, 0, 0, 0, 0, mappings[1].length + 1, Array.new(mappings[1].length + 1, 0))
      patch(header, 12 + mappings[1].fetch(input.first) * 2, header.bytesize)
      header << set
      patch(header, 2, header.bytesize)
      header << coverage(input.first)
      mappings.each_with_index { |mapping, index| patch(header, 4 + index * 2, header.bytesize); header << classes(mapping) }
      header
    end
  end

  def gdef(mapping, mark_classes: {}, mark_sets: [])
    header = u16(1, mark_sets.empty? ? 0 : 2, mark_sets.empty? ? 12 : 14, 0, 0, 0)
    header << u16(0) unless mark_sets.empty?
    header << classes(mapping)
    unless mark_classes.empty?
      patch(header, 10, header.bytesize)
      header << classes(mark_classes)
    end
    unless mark_sets.empty?
      patch(header, 12, header.bytesize)
      sets, body = u16(1, mark_sets.length), "".b
      mark_sets.each { |ids| sets << [4 + mark_sets.length * 4 + body.bytesize].pack("N"); body << coverage(ids) }
      header << sets << body
    end
    header
  end

  def glyphs(font, ids)
    ids.each_with_index.map { |id, i| T::Glyph.new(font, id, i, i + 1, i * 10, 10) }
  end

  def shape(font, ids, **options) = T::Shaper.new.shape(glyphs(font, ids), size: 10, **options)

  def test_all_chained_context_formats_match_backtrack_input_and_lookahead
    [1, 2, 3].each do |format|
      rule = chained(format, input: [3, 4], back: [2, 1], ahead: [5, 6], actions: [[1, 1]])
      font = Font.new(GSUB: layout([lookup(6, rule), lookup(1, single(4 => 40))]))
      assert_equal [1, 2, 3, 40, 5, 6], shape(font, [1, 2, 3, 4, 5, 6]).map(&:id)
      [[1, 9, 3, 4, 5, 6], [1, 2, 3, 9, 5, 6], [1, 2, 3, 4, 9, 6], [3, 4, 5, 6]].each do |ids|
        assert_equal ids, shape(font, ids).map(&:id)
      end
    end
  end

  def test_context_positions_survive_ligatures_and_ignored_marks
    [1, 2, 3].each do |format|
      # Sequence indices refer to the current matched sequence after edits.
      rule = chained(format, input: [1, 2, 3], actions: [[0, 1], [1, 2]])
      font = Font.new(GSUB: layout([lookup(6, rule, flags: 8), lookup(4, ligature([1, 2], 10), flags: 8), lookup(1, single(3 => 30))]), GDEF: gdef({1 => 1, 2 => 1, 3 => 1, 99 => 3}))
      result = shape(font, [1, 99, 2, 3])
      assert_equal [10, 99, 30], result.map(&:id)
      assert_equal [0, 3], [result.first.start, result.first.finish]
    end
  end

  def test_context_input_is_skipped_but_lookahead_is_not
    rule = chained(1, input: [1, 1], ahead: [1], actions: [[0, 1]])
    font = Font.new(GSUB: layout([lookup(6, rule), lookup(1, single(1 => 2))]))
    assert_equal [2, 1, 2, 1, 1], shape(font, [1, 1, 1, 1, 1]).map(&:id)
  end

  def test_mark_filtering_sets_and_attachment_classes
    [0x100, 0x10].each do |flags|
      # Mark 99 must be skipped, mark 98 must participate.
      font = Font.new(GSUB: layout([lookup(4, ligature([1, 98, 2], 10), flags: flags)]),
                      GDEF: gdef({1 => 1, 2 => 1, 98 => 3, 99 => 3}, mark_classes: {98 => 1, 99 => 2}, mark_sets: [[98]]))
      assert_equal [10, 99], shape(font, [1, 99, 98, 2]).map(&:id)
    end
  end

  def test_script_language_required_features_and_lookup_order
    font = Font.new(GSUB: layout([lookup(1, single(1 => 2)), lookup(1, single(2 => 3)), lookup(1, single(1 => 4))],
      features: {"liga" => [1, 0], "calt" => [2]}, scripts: {"latn" => {nil => [0], "TRK " => [1]}, "kana" => {nil => [1]}}))
    assert_equal [3], shape(font, [1]).map(&:id)
    assert_equal [4], shape(font, [1], language: "TRK ").map(&:id)
    assert_equal [4], shape(font, [1], script: "kana").map(&:id)
    assert_equal [1], shape(font, [1], script: "hani").map(&:id)
    required = Font.new(GSUB: layout([lookup(1, single(1 => 9))], features: {"rlig" => [0]}, scripts: {"DFLT" => {nil => []}}, required: 0))
    assert_equal [9], shape(required, [1], script: "hani").map(&:id)
  end

  def pair(first, second, values1, values2 = [], first_format: 4, second_format: 0)
    set = u16(1, second, values1, values2)
    u16(1, 12 + set.bytesize, first_format, second_format, 1, 12) + set + coverage(first)
  end

  def test_pair_positioning_accumulates_all_lookups_and_both_value_records
    font = Font.new(GPOS: layout([lookup(2, pair(1, 2, [50, -100], [-20, -30], first_format: 5, second_format: 5)), lookup(2, pair(1, 2, [-40]))], features: {"kern" => [0, 1]}))
    result = shape(font, [1, 2, 3])
    assert_in_delta 0.5, result[0].x
    assert_in_delta 8.6, result[0].advance
    assert_in_delta 8.4, result[1].x
    assert_in_delta 9.7, result[1].advance
    assert_in_delta 18.3, result[2].x
  end

  def test_class_pair_matrix_and_extension_lookup
    # Two classes in each dimension; only class1/class1 changes advance.
    subtable = u16(2, 24, 4, 0, 30, 40, 2, 2, 0, 0, 0, -75) + coverage(1) + classes(1 => 1) + classes(2 => 1)
    extension = u16(1, 2) + [8].pack("N") + subtable
    font = Font.new(GPOS: layout([lookup(9, extension)], features: {"kern" => [0]}))
    assert_in_delta 9.25, shape(font, [1, 2]).first.advance
    assert_in_delta 10, shape(font, [1, 3]).first.advance
    gsub_extension = u16(1, 1) + [8].pack("N") + single(1 => 5)
    assert_equal [5], shape(Font.new(GSUB: layout([lookup(7, gsub_extension)])), [1]).map(&:id)
  end

  def test_device_deltas_and_pair_iteration_with_second_values
    [1, 2, 3].each do |format|
      bits = 1 << format
      packed_delta = ((1 << bits) - 1) << (16 - bits) # -1 at 10 ppem
      set = u16(1, 2, -100, 8, 10, 10, format, packed_delta)
      subtable = u16(1, 12 + set.bytesize, 0x44, 0, 1, 12) + set + coverage(1)
      font = Font.new(GPOS: layout([lookup(2, subtable)], features: {"kern" => [0]}))
      assert_in_delta 8, shape(font, [1, 2]).first.advance
    end
    # A present second record means that glyph is consumed by this lookup.
    font = Font.new(GPOS: layout([lookup(2, pair(1, 1, [-100], [-50], second_format: 4))], features: {"kern" => [0]}))
    assert_equal [9, 9.5, 9, 9.5], shape(font, [1, 1, 1, 1]).map(&:advance)
    overlap = Font.new(GPOS: layout([lookup(2, pair(1, 1, [-100]))], features: {"kern" => [0]}))
    assert_equal [9, 9, 9, 10], shape(overlap, [1, 1, 1, 1]).map(&:advance)
  end

  def test_source_script_inference_and_empty_shape
    font = Font.new(GSUB: layout([lookup(1, single(1 => 2)), lookup(1, single(1 => 3))],
      features: {"liga" => [0], "calt" => [1]}, scripts: {"latn" => {nil => [0]}, "kana" => {nil => [1]}}))
    input = [T::Glyph.new(font, 1, 0, 1, 0, 10), T::Glyph.new(font, 1, 1, 4, 0, 10)]
    result = T::Shaper.new.shape(input, size: 10, text: "aあ")
    assert_equal [2, 3], result.map(&:id)
    assert_equal [0, 10], result.map(&:x)
    assert_empty T::Shaper.new.shape([], size: 10)
  end

  def test_bounds_reserved_values_and_recursive_lookups_fail_explicitly
    recursive = chained(3, input: [1], actions: [[0, 0]])
    assert_raises(Zaniah::Error) { shape(Font.new(GSUB: layout([lookup(6, recursive)])), [1]) }
    assert_raises(Zaniah::Error) { shape(Font.new(GSUB: layout([lookup(1, single(1 => 2), flags: 0x20)])), [1]) }
    bad_value = pair(1, 2, [0], first_format: 0x100)
    assert_raises(Zaniah::Error) { shape(Font.new(GPOS: layout([lookup(2, bad_value)], features: {"kern" => [0]})), [1, 2]) }
    assert_raises(Alhena::InvalidFont) { shape(Font.new(GSUB: layout([lookup(1, u16(2, 1000, 1, 5))])), [1]) }
  end

  def test_truncated_and_mutated_layout_tables_are_bounded
    tables = [1, 2, 3].map do |format|
      layout([lookup(6, chained(format, input: [1, 2], actions: [[1, 1]])), lookup(1, single(2 => 20))])
    end
    tables.each do |table|
      table.bytesize.times do |length|
        assert_raises(Zaniah::Error, Alhena::InvalidFont) { shape(Font.new(GSUB: table.byteslice(0, length)), [1, 2]) }
      end
    end
    random = Random.new(821)
    500.times do
      bytes = tables.sample(random: random).dup
      bytes.setbyte(random.rand(bytes.bytesize), random.rand(256))
      begin
        result = shape(Font.new(GSUB: bytes), [1, 2])
        assert_operator result.length, :<=, 2
      rescue Zaniah::Error, Alhena::InvalidFont
        assert true
      end
    end
  end
end
