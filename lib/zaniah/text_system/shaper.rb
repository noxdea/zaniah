# frozen_string_literal: true

module Zaniah
  module TextSystem
    # Horizontal Latin/CJK/kana shaping, not complex-script reordering.
    # OpenType GSUB 1/4/6/7; GPOS 2/9; GDEF lookup filtering; legacy kern.
    class Shaper
      def initialize = (@lookups, @filters = {}, {})

      def shape(glyphs, size:, text: nil, script: nil, language: nil)
        raise ArgumentError, "font size must be finite and positive" unless size.is_a?(Numeric) && size.finite? && size.positive?
        runs, previous = [], nil
        inferred = glyphs.map { |glyph| script || (text && script_for(text.byteslice(glyph.start...glyph.finish))) }
        inherited = inferred.compact.first || "latn"
        glyphs.each_with_index do |glyph, i|
          inherited = inferred[i] || inherited
          key = [glyph.font, inherited.to_s]
          runs << [key, []] unless key == previous
          runs.last[1] << glyph
          previous = key
        end
        x = 0.0
        runs.flat_map do |(font, tag), run|
          if font.tables.key?("GSUB")
            data = font.table("GSUB")
            lookups(data, font, "GSUB", %w[liga calt], tag, language).each do |lookup|
              index = 0
              index = substitute(data, lookup, run, index, size, 0, []) || index + 1 while index < run.length
            end
          end
          placements, advances = positioning(run, size, tag, language)
          run.each_with_index.map do |glyph, i|
            advance = glyph.advance + advances[i]
            placed = Glyph.new(font, glyph.id, glyph.start, glyph.finish, x + placements[i], advance)
            x += advance
            placed
          end
        end
      end

      private

      def script_for(text)
        return unless text
        case text
        when /\p{Latin}/ then "latn"
        when /[\p{Hiragana}\p{Katakana}]/ then "kana"
        when /\p{Han}/ then "hani"
        when /\p{Hangul}/ then "hang"
        when /\p{Greek}/ then "grek"
        when /\p{Cyrillic}/ then "cyrl"
        end
      end

      def words(data, offset, count)
        data.check(offset, count * 2)
        Array.new(count) { |i| data.u16(offset + i * 2) }
      end

      def records(data, offset, base = offset)
        count = data.u16(offset)
        data.check(offset + 2, count * 6)
        Array.new(count) { |i| [data.bytes(offset + 2 + i * 6, 4), base + data.u16(offset + 6 + i * 6)] }.to_h
      end

      def lookups(data, font, tag, features, script, language)
        @lookups[[font, tag, script, language, features]] ||= begin
          raise Error, "unsupported OpenType layout version" unless data.u16(0) == 1 && data.u16(2) <= 1
          scripts = records(data, data.u16(4))
          selected = scripts[script] || scripts["DFLT"]
          indices = []
          if selected
            languages = records(data, selected + 2, selected)
            lang = (language && languages[language.to_s]) || (data.u16(selected).positive? && selected + data.u16(selected))
            if lang
              required = data.u16(lang + 2)
              candidates = words(data, lang + 6, data.u16(lang + 4))
              candidates.unshift(required) unless required == 0xffff
              feature_list = data.u16(6)
              count = data.u16(feature_list)
              data.check(feature_list + 2, count * 6)
              candidates.uniq.each do |index|
                raise Error, "invalid OpenType feature index" if index >= count
                at = feature_list + 2 + index * 6
                next unless index == required || features.include?(data.bytes(at, 4))
                feature = feature_list + data.u16(at + 4)
                indices.concat(words(data, feature + 4, data.u16(feature + 2)))
              end
            end
          end
          list = data.u16(8)
          offsets = words(data, list + 2, data.u16(list))
          indices.uniq.sort.map do |index|
            raise Error, "invalid OpenType lookup index" if index >= offsets.length
            list + offsets[index]
          end
        end
      end

      def coverage(data, offset, glyph)
        case data.u16(offset)
        when 1
          count = data.u16(offset + 2)
          data.check(offset + 4, count * 2)
          index = (0...count).bsearch { |i| data.u16(offset + 4 + i * 2) >= glyph }
          index if index && data.u16(offset + 4 + index * 2) == glyph
        when 2
          count = data.u16(offset + 2)
          data.check(offset + 4, count * 6)
          index = (0...count).bsearch { |i| data.u16(offset + 6 + i * 6) >= glyph }
          return unless index
          at = offset + 4 + index * 6
          first, last = data.u16(at), data.u16(at + 2)
          raise Error, "reversed OpenType coverage range" if last < first
          data.u16(at + 4) + glyph - first if glyph.between?(first, last)
        else raise Error, "invalid OpenType coverage format"
        end
      end

      def glyph_class(data, at, glyph)
        return 0 if at.zero?
        case data.u16(at)
        when 1
          first, count = data.u16(at + 2), data.u16(at + 4)
          data.check(at + 6, count * 2)
          glyph.between?(first, first + count - 1) ? data.u16(at + 6 + (glyph - first) * 2) : 0
        when 2
          count = data.u16(at + 2)
          data.check(at + 4, count * 6)
          index = (0...count).bsearch { |i| data.u16(at + 6 + i * 6) >= glyph }
          return 0 unless index && data.u16(at + 4 + index * 6) <= glyph
          data.u16(at + 8 + index * 6)
        else raise Error, "invalid OpenType class definition"
        end
      end

      def filter(data, lookup, font)
        @filters[[data, lookup, font]] ||= begin
          flags = data.u16(lookup + 2)
          raise Error, "reserved OpenType lookup flags" unless (flags & 0xe0).zero?
          gdef = font.tables.key?("GDEF") && font.table("GDEF")
          if flags & 0xff1e != 0
            raise Error, "lookup filtering requires GDEF glyph classes" unless gdef && gdef.u16(4).positive?
            if flags >> 8 != 0 && flags & 0x18 == 0 && gdef.u16(10).zero?
              raise Error, "lookup filtering requires GDEF mark attachment classes"
            end
          end
          mark_set = nil
          if flags & 0x10 != 0
            raise Error, "missing GDEF mark filtering sets" unless gdef && gdef.u16(0) == 1 && gdef.u16(2) >= 2
            sets = gdef.u16(12)
            raise Error, "missing GDEF mark filtering sets" if sets.zero?
            index = data.u16(lookup + 6 + data.u16(lookup + 4) * 2)
            raise Error, "invalid GDEF mark filtering set" unless gdef.u16(sets) == 1 && index < gdef.u16(sets + 2)
            mark_set = sets + gdef.u32(sets + 4 + index * 4)
          end
          lambda do |glyph|
            next false unless gdef && flags & 0xff1e != 0
            klass = glyph_class(gdef, gdef.u16(4), glyph.id)
            next true if (klass == 1 && flags & 2 != 0) || (klass == 2 && flags & 4 != 0) || (klass == 3 && flags & 8 != 0)
            next false unless klass == 3
            next coverage(gdef, mark_set, glyph.id).nil? if mark_set
            flags >> 8 != 0 && glyph_class(gdef, gdef.u16(10), glyph.id) != flags >> 8
          end
        end
      end

      def next_index(glyphs, index, direction, ignored)
        index += direction
        index += direction while index.between?(0, glyphs.length - 1) && ignored.call(glyphs[index])
        index if index.between?(0, glyphs.length - 1)
      end

      def subtables(data, lookup, extension)
        type = data.u16(lookup)
        words(data, lookup + 6, data.u16(lookup + 4)).each do |offset|
          raise Error, "null OpenType subtable" if offset.zero?
          at, actual = lookup + offset, type
          if type == extension
            raise Error, "invalid OpenType extension" unless data.u16(at) == 1
            actual = data.u16(at + 2)
            raise Error, "recursive OpenType extension" if actual == extension
            at += data.u32(at + 4)
          end
          yield actual, at
        end
      end

      def substitute(data, lookup, glyphs, index, size, depth, contexts)
        raise Error, "OpenType contextual lookup recursion limit" if depth > 8
        return unless (glyph = glyphs[index])
        ignored = filter(data, lookup, glyph.font)
        subtables(data, lookup, 7) do |type, at|
          next unless [1, 4, 6].include?(type)
          format = data.u16(at)
          cov = type == 6 && format == 3 ? 0 : coverage(data, at + data.u16(at + 2), glyph.id)
          next unless cov
          case type
          when 1
            id = case format
            when 1 then (glyph.id + data.i16(at + 4)) & 0xffff
            when 2
              substitutes = words(data, at + 6, data.u16(at + 4))
              raise Error, "OpenType substitute coverage exceeds array" if cov >= substitutes.length
              substitutes[cov]
            else raise Error, "invalid single substitution format"
            end
            glyphs[index] = Glyph.new(glyph.font, id, glyph.start, glyph.finish, glyph.x, glyph.font.advance(id, size: size))
            return index + 1
          when 4
            raise Error, "invalid ligature substitution format" unless format == 1
            sets = words(data, at + 6, data.u16(at + 4))
            next if cov >= sets.length || sets[cov].zero?
            set = at + sets[cov]
            words(data, set + 2, data.u16(set)).each do |offset|
              ligature = set + offset
              id, count = data.u16(ligature), data.u16(ligature + 2)
              raise Error, "empty OpenType ligature" if count.zero?
              expected = words(data, ligature + 4, count - 1)
              positions, cursor = [index], index
              matched = expected.all? do |expected_id|
                cursor = next_index(glyphs, cursor, 1, ignored)
                positions << cursor if cursor
                cursor && glyphs[cursor].id == expected_id
              end
              next unless matched
              ending = glyphs[positions.last].finish
              glyphs[index] = Glyph.new(glyph.font, id, glyph.start, ending, glyph.x, glyph.font.advance(id, size: size))
              remove_positions(glyphs, positions.drop(1), contexts)
              return index + 1
            end
          when 6
            ending = contextual(data, at, format, cov, glyphs, index, size, depth, contexts, ignored)
            return ending if ending
          end
        end
        nil
      end

      def remove_positions(glyphs, removed, contexts)
        contexts.each do |context|
          context[:positions] = context[:positions].reject { |i| removed.include?(i) }.map { |i| i - removed.count { |j| j < i } }
          context[:end] -= removed.count { |i| i < context[:end] }
        end
        removed.reverse_each { |i| glyphs.delete_at(i) }
      end

      def contextual(data, at, format, cov, glyphs, index, size, depth, contexts, ignored)
        if format == 3
          rules, definitions = [at + 2], nil
        elsif [1, 2].include?(format)
          definitions = format == 2 ? words(data, at + 4, 3).map { |offset| at + offset } : nil
          set_index = definitions ? glyph_class(data, definitions[1], glyphs[index].id) : cov
          offset = format == 1 ? 4 : 10
          sets = words(data, at + offset + 2, data.u16(at + offset))
          return if set_index >= sets.length || sets[set_index].zero?
          set = at + sets[set_index]
          rules = words(data, set + 2, data.u16(set)).map { |distance| set + distance }
        else raise Error, "invalid chained context format"
        end
        rules.each do |cursor|
          sequences = []
          3.times do |part|
            count = data.u16(cursor)
            cursor += 2
            raise Error, "empty context input" if part == 1 && count.zero?
            count -= 1 if part == 1 && format != 3
            sequences << words(data, cursor, count)
            cursor += count * 2
          end
          match = lambda do |part, value, position|
            id = glyphs[position].id
            if format == 3
              !coverage(data, at + value, id).nil?
            elsif definitions
              glyph_class(data, definitions[part], id) == value
            else
              id == value
            end
          end
          previous = index
          next unless sequences[0].all? { |value| previous = next_index(glyphs, previous, -1, ignored); previous && match.call(0, value, previous) }
          positions, current = [index], index
          input = sequences[1].dup
          next if format == 3 && !match.call(1, input.shift, index)
          next unless input.all? do |value|
            current = next_index(glyphs, current, 1, ignored)
            positions << current if current
            current && match.call(1, value, current)
          end
          following = current
          next unless sequences[2].all? { |value| following = next_index(glyphs, following, 1, ignored); following && match.call(2, value, following) }
          count = data.u16(cursor)
          actions = words(data, cursor + 2, count * 2).each_slice(2).to_a
          list = data.u16(8)
          lookups = words(data, list + 2, data.u16(list))
          context = {positions: positions, end: current + 1}
          contexts << context
          actions.each do |sequence, lookup_index|
            raise Error, "invalid contextual lookup index" if lookup_index >= lookups.length
            target = context[:positions][sequence]
            substitute(data, list + lookups[lookup_index], glyphs, target, size, depth + 1, contexts) if target
          end
          contexts.pop
          return context[:end]
        end
        nil
      end

      def positioning(glyphs, size, script, language)
        placements, advances = Array.new(glyphs.length, 0.0), Array.new(glyphs.length, 0.0)
        return [placements, advances] if glyphs.empty?
        font, active = glyphs.first.font, []
        factor = size.to_f / font.units_per_em
        if font.tables.key?("GPOS")
          data = font.table("GPOS")
          active = lookups(data, font, "GPOS", ["kern"], script, language)
          active.each do |lookup|
            ignored = filter(data, lookup, font)
            index = 0
            while index < glyphs.length
              following = next_index(glyphs, index, 1, ignored)
              break unless following
              next_cursor = index + 1
              subtables(data, lookup, 9) do |type, at|
                next unless type == 2
                cov = coverage(data, at + data.u16(at + 2), glyphs[index].id)
                next unless cov
                pair = pair_adjustment(data, at, cov, glyphs[index].id, glyphs[following].id, size, factor)
                next unless pair
                first, second, second_format = pair
                placements[index] += first[0]
                advances[index] += first[1]
                placements[following] += second[0]
                advances[following] += second[1]
                next_cursor = second_format.zero? ? following : following + 1
                break
              end
              index = next_cursor
            end
          end
        end
        if active.empty?
          glyphs.each_cons(2).with_index { |(left, right), i| advances[i] += legacy_kern(font, left.id, right.id) * factor }
        end
        [placements, advances]
      end

      def pair_adjustment(data, at, coverage_index, left, right, size, factor)
        format, first_format, second_format = data.u16(at), data.u16(at + 4), data.u16(at + 6)
        raise Error, "reserved OpenType value format" unless ((first_format | second_format) & 0xff00).zero?
        first_size, second_size = first_format.digits(2).sum * 2, second_format.digits(2).sum * 2
        stride = first_size + second_size
        if format == 1
          sets = words(data, at + 10, data.u16(at + 8))
          return if coverage_index >= sets.length
          parent = at + sets[coverage_index]
          count = data.u16(parent)
          data.check(parent + 2, count * (stride + 2))
          index = (0...count).bsearch { |j| data.u16(parent + 2 + j * (stride + 2)) >= right }
          return unless index && data.u16(parent + 2 + index * (stride + 2)) == right
          record = parent + 4 + index * (stride + 2)
        elsif format == 2
          parent = at
          class1 = glyph_class(data, at + data.u16(at + 8), left)
          class2 = glyph_class(data, at + data.u16(at + 10), right)
          count1, count2 = data.u16(at + 12), data.u16(at + 14)
          data.check(at + 16, count1 * count2 * stride)
          raise Error, "OpenType pair class exceeds matrix" unless class1 < count1 && class2 < count2
          record = at + 16 + (class1 * count2 + class2) * stride
        else raise Error, "invalid pair positioning format"
        end
        [value_record(data, record, first_format, parent, size, factor),
         value_record(data, record + first_size, second_format, parent, size, factor), second_format]
      end

      def value_record(data, at, format, parent, size, factor)
        values = Array.new(8, 0)
        8.times do |bit|
          next if format & (1 << bit) == 0
          values[bit] = bit < 4 ? data.i16(at) : data.u16(at)
          at += 2
        end
        # yAdvance is irrelevant to horizontal text; vertical placement needs
        # a native shaper with a two-dimensional glyph attachment model.
        raise Error, "vertical pair placement requires a native shaper" unless values[1].zero? && values[5].zero?
        placement, advance = values[0] * factor, values[2] * factor
        placement += device_delta(data, parent + values[4], size.round) unless values[4].zero?
        advance += device_delta(data, parent + values[6], size.round) unless values[6].zero?
        [placement, advance]
      end

      def device_delta(data, at, ppem)
        first, last, format = data.u16(at), data.u16(at + 2), data.u16(at + 4)
        raise Error, "unsupported OpenType device delta format" unless (1..3).cover?(format)
        raise Error, "reversed device ppem range" if last < first
        bits = 1 << format
        data.check(at + 6, ((last - first + 1) * bits + 15) / 16 * 2)
        return 0 unless ppem.between?(first, last)
        index, mask = ppem - first, (1 << bits) - 1
        value = (data.u16(at + 6 + index * bits / 16 * 2) >> (16 - bits - index * bits % 16)) & mask
        value >= 1 << (bits - 1) ? value - (1 << bits) : value
      end

      def legacy_kern(font, left, right)
        return 0 unless font.tables.key?("kern")
        data = font.table("kern")
        return 0 unless data.u16(0).zero?
        cursor, result = 4, 0
        data.u16(2).times do
          length, flags = data.u16(cursor + 2), data.u16(cursor + 4)
          raise Error, "invalid kern table length" if length < 6
          data.check(cursor, length)
          if flags >> 8 == 0 && flags & 7 == 1
            count = data.u16(cursor + 6)
            raise Error, "kern pairs exceed subtable" if 14 + count * 6 > length
            pair = (left << 16) | right
            index = (0...count).bsearch { |j| data.u32(cursor + 14 + j * 6) >= pair }
            if index && data.u32(cursor + 14 + index * 6) == pair
              value = data.i16(cursor + 18 + index * 6)
              result = flags & 8 == 0 ? result + value : value
            end
          end
          cursor += length
        end
        result
      end
    end
  end
end
