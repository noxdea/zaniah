# frozen_string_literal: true

require_relative "bidi_data"

module Zaniah
  module Unicode
    # UAX #9 paragraph resolution. Indices in levels/order are Unicode scalar
    # positions; text layout converts them to UTF-8 byte boundaries.
    module Bidi
      REMOVED = %i[RLE LRE RLO LRO PDF BN].freeze
      ISOLATES = %i[RLI LRI FSI].freeze
      NEUTRALS = %i[B S WS ON RLI LRI FSI PDI].freeze
      MAX_DEPTH = 125
      Result = Data.define(:paragraph_level, :levels, :visual_order, :types) do
        def direction = paragraph_level.odd? ? :rtl : :ltr
      end

      module_function

      def bidi_class(codepoint)
        range = BidiData::CLASS_RANGES.bsearch { |_, last, _| last >= codepoint }
        range && range[0] <= codepoint ? range[2] : :L
      end

      def mirrored(codepoint) = BidiData::MIRRORS.fetch(codepoint, codepoint)

      def control?(codepoint) = codepoint == 0x061C || codepoint == 0x200E || codepoint == 0x200F ||
        (0x202A..0x202E).cover?(codepoint) || (0x2066..0x2069).cover?(codepoint)

      def resolve(text, direction: :auto)
        raise ArgumentError, "text must be valid UTF-8" unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
        raise ArgumentError, "direction must be auto, ltr, or rtl" unless %i[auto ltr rtl].include?(direction)
        points = text.codepoints
        original = points.map { |point| bidi_class(point) }
        base = direction == :auto ? first_strong(original, 0, original.length) : (direction == :rtl ? 1 : 0)
        levels, types = explicit_levels(original, base)
        sequences(types, levels, original).each do |indices, sos, eos|
          weak_types(types, indices, sos)
          paired_brackets(points, original, types, levels, indices, sos)
          neutral_types(types, levels, indices, sos, eos)
          implicit_levels(types, levels, indices)
        end
        reorder_levels(original, levels, base)
        Result.new(base, levels.freeze, visual_order(levels).freeze, types.freeze)
      end

      # Resolve weak/neutral types on the whole paragraph, then apply L1/L2
      # independently to a display line after logical line breaking.
      def line_result(result, text, first, finish)
        raise ArgumentError, "invalid line range" unless first.is_a?(Integer) && finish.is_a?(Integer) && first.between?(0, finish) && finish <= result.levels.length
        return result if first.zero? && finish == result.levels.length
        original = text.codepoints.slice(first...finish).map { |point| bidi_class(point) }
        levels = result.levels.slice(first...finish).dup
        reorder_levels(original, levels, result.paragraph_level)
        Result.new(result.paragraph_level, levels.freeze, visual_order(levels).freeze,
          result.types.slice(first...finish).freeze)
      end

      def first_strong(types, first, finish)
        depth = 0
        (first...finish).each do |index|
          type = types[index]
          if ISOLATES.include?(type)
            depth += 1
          elsif type == :PDI
            depth -= 1 if depth.positive?
          elsif depth.zero?
            return 0 if type == :L
            return 1 if type == :R || type == :AL
          end
        end
        0
      end

      def matching_isolates(types)
        stack, matches = [], {}
        types.each_with_index do |type, index|
          stack << index if ISOLATES.include?(type)
          if type == :PDI && !stack.empty?
            first = stack.pop
            matches[first] = index
          end
        end
        matches
      end

      def explicit_levels(original, base)
        matches = matching_isolates(original)
        stack = [[base, nil, false]]
        overflow_isolate = overflow_embedding = valid_isolate = 0
        levels = Array.new(original.length)
        types = original.dup
        original.each_with_index do |type, index|
          current, override = stack.last
          case type
          when :RLE, :RLO, :LRE, :LRO
            next_level = (type == :RLE || type == :RLO) ? (current + 1) | 1 : (current + 2) & ~1
            if next_level <= MAX_DEPTH && overflow_isolate.zero? && overflow_embedding.zero?
              stack << [next_level, type == :RLO ? :R : (type == :LRO ? :L : nil), false]
            elsif overflow_isolate.zero?
              overflow_embedding += 1
            end
          when :RLI, :LRI, :FSI
            levels[index] = current
            types[index] = override if override
            rtl = type == :RLI || (type == :FSI && first_strong(original, index + 1, matches.fetch(index, original.length)) == 1)
            next_level = rtl ? (current + 1) | 1 : (current + 2) & ~1
            if next_level <= MAX_DEPTH && overflow_isolate.zero? && overflow_embedding.zero?
              stack << [next_level, nil, true]
              valid_isolate += 1
            else
              overflow_isolate += 1
            end
          when :PDI
            if overflow_isolate.positive?
              overflow_isolate -= 1
            elsif valid_isolate.positive?
              overflow_embedding = 0
              stack.pop until stack.last[2]
              stack.pop
              valid_isolate -= 1
            end
            levels[index] = stack.last[0]
            types[index] = stack.last[1] || type
          when :PDF
            if overflow_isolate.zero?
              if overflow_embedding.positive?
                overflow_embedding -= 1
              elsif stack.length > 1 && !stack.last[2]
                stack.pop
              end
            end
          when :B
            levels[index] = base
            stack = [[base, nil, false]]
            overflow_isolate = overflow_embedding = valid_isolate = 0
          when :BN
            nil
          else
            levels[index] = current
            types[index] = override if override
          end
        end
        [levels, types]
      end

      def sequences(types, levels, original)
        active = levels.each_index.select { |index| levels[index] }
        return [] if active.empty?
        runs = []
        active.each do |index|
          runs << [] if runs.empty? || levels[runs.last.last] != levels[index]
          runs.last << index
        end
        run_at = runs.each_with_index.each_with_object({}) { |(run, number), map| run.each { |index| map[index] = number } }
        matches = matching_isolates(original)
        forward, inbound = {}, {}
        runs.each_with_index do |run, number|
          last = run.last
          next unless ISOLATES.include?(original[last]) && (ending = matches[last]) && run_at[ending]
          forward[number] = run_at[ending]
          inbound[run_at[ending]] = true
        end
        seen = {}
        runs.each_index.filter_map do |start|
          next if inbound[start] || seen[start]
          indices, cursor = [], start
          while cursor && !seen[cursor]
            seen[cursor] = true
            indices.concat(runs[cursor])
            cursor = forward[cursor]
          end
          first, last = indices.first, indices.last
          before = active.bsearch_index { |index| index >= first }
          after = active.bsearch_index { |index| index > last }
          previous_level = before && before.positive? ? levels[active[before - 1]] : levels[active.first] & 1
          next_level = after && !ISOLATES.include?(original[last]) ? levels[active[after]] : levels[active.first] & 1
          sos = [levels[first], previous_level].max.odd? ? :R : :L
          eos = [levels[last], next_level].max.odd? ? :R : :L
          [indices, sos, eos]
        end
      end

      def weak_types(types, indices, sos)
        # W1
        indices.each_with_index do |index, position|
          next unless types[index] == :NSM
          previous = position.zero? ? sos : types[indices[position - 1]]
          types[index] = ISOLATES.include?(previous) || previous == :PDI ? :ON : previous
        end
        # W2, then W3
        strong = sos
        indices.each do |index|
          type = types[index]
          types[index] = :AN if type == :EN && strong == :AL
          strong = type if %i[L R AL].include?(type)
        end
        indices.each { |index| types[index] = :R if types[index] == :AL }
        # W4
        indices.each_cons(3) do |left, middle, right|
          value = types[middle]
          types[middle] = :EN if value == :ES && types[left] == :EN && types[right] == :EN
          types[middle] = types[left] if value == :CS && %i[EN AN].include?(types[left]) && types[left] == types[right]
        end
        # W5
        position = 0
        while position < indices.length
          unless types[indices[position]] == :ET
            position += 1
            next
          end
          ending = position + 1
          ending += 1 while ending < indices.length && types[indices[ending]] == :ET
          if (position.positive? && types[indices[position - 1]] == :EN) ||
              (ending < indices.length && types[indices[ending]] == :EN)
            (position...ending).each { |cursor| types[indices[cursor]] = :EN }
          end
          position = ending
        end
        # W6, W7
        indices.each { |index| types[index] = :ON if %i[ES ET CS].include?(types[index]) }
        strong = sos
        indices.each do |index|
          type = types[index]
          types[index] = :L if type == :EN && strong == :L
          strong = type if %i[L R].include?(type)
        end
      end

      def paired_brackets(points, original, types, levels, indices, sos)
        stack, pairs = [], []
        indices.each_with_index do |index, position|
          next unless types[index] == :ON && (pair = BidiData::BRACKETS[points[index]])
          if pair[1] == :o
            return if stack.length == 63
            stack << [pair[0], position]
          else
            candidate = stack.rindex { |point, _| point == points[index] || ([0x3009, 0x232A].include?(point) && [0x3009, 0x232A].include?(points[index])) }
            next unless candidate
            pairs << [stack[candidate][1], position]
            stack.slice!(candidate..-1)
          end
        end
        pairs.sort_by(&:first).each do |first, last|
          embedding = levels[indices[first]].odd? ? :R : :L
          enclosed = indices[(first + 1)...last].map { |index| strong_type(types[index]) }.compact
          target = if enclosed.include?(embedding)
            embedding
          elsif enclosed.any?
            before = first - 1
            before -= 1 while before >= 0 && !strong_type(types[indices[before]])
            prior = before.negative? ? sos : strong_type(types[indices[before]])
            prior == embedding ? embedding : (embedding == :L ? :R : :L)
          end
          next unless target
          [first, last].each do |position|
            types[indices[position]] = target
            following = position + 1
            while following < indices.length && original[indices[following]] == :NSM
              types[indices[following]] = target
              following += 1
            end
          end
        end
      end

      def strong_type(type) = %i[EN AN R].include?(type) ? :R : (type == :L ? :L : nil)

      def neutral_types(types, levels, indices, sos, eos)
        position = 0
        while position < indices.length
          unless NEUTRALS.include?(types[indices[position]])
            position += 1
            next
          end
          ending = position + 1
          ending += 1 while ending < indices.length && NEUTRALS.include?(types[indices[ending]])
          left = position.zero? ? sos : strong_type(types[indices[position - 1]])
          right = ending == indices.length ? eos : strong_type(types[indices[ending]])
          (position...ending).each do |cursor|
            index = indices[cursor]
            types[index] = left == right ? left : (levels[index].odd? ? :R : :L)
          end
          position = ending
        end
      end

      def implicit_levels(types, levels, indices)
        indices.each do |index|
          type = types[index]
          levels[index] += if levels[index].odd?
            %i[L EN AN].include?(type) ? 1 : 0
          elsif type == :R
            1
          elsif %i[EN AN].include?(type)
            2
          else
            0
          end
        end
      end

      def reorder_levels(original, levels, base)
        original.each_index do |index|
          next unless %i[S B].include?(original[index])
          levels[index] = base
          cursor = index - 1
          while cursor >= 0 && (%i[WS RLI LRI FSI PDI].include?(original[cursor]) || levels[cursor].nil?)
            levels[cursor] = base if levels[cursor]
            cursor -= 1
          end
        end
        cursor = original.length - 1
        while cursor >= 0 && (%i[WS RLI LRI FSI PDI].include?(original[cursor]) || levels[cursor].nil?)
          levels[cursor] = base if levels[cursor]
          cursor -= 1
        end
      end

      def visual_order(levels)
        order = levels.each_index.select { |index| levels[index] }
        return order if order.empty?
        highest = order.map { |index| levels[index] }.max
        lowest_odd = order.map { |index| levels[index] }.select(&:odd?).min
        return order unless lowest_odd
        highest.downto(lowest_odd) do |level|
          first = 0
          while first < order.length
            if levels[order[first]] >= level
              last = first + 1
              last += 1 while last < order.length && levels[order[last]] >= level
              order[first...last] = order[first...last].reverse
              first = last
            else
              first += 1
            end
          end
        end
        order
      end
    end
  end
end
