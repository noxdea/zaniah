# frozen_string_literal: true

require_relative "font_db"
require_relative "glyph"
require_relative "line_layout"
require_relative "shaper"

module Zaniah
  module TextSystem
    # Layout-only state can belong to a background worker without GPU atlases or
    # sharing the rendering thread's mutable caches. Providers are owner-local.
    class Typesetter
      EMPTY_FEATURES = {}.freeze
      attr_reader :font_db, :font, :shaper, :segmenter

      def initialize(font: nil, font_db: Zaniah.configuration.font_db, capacity: 2000,
        shaper: Zaniah.configuration.shaper, segmenter: Zaniah.configuration.segmenter)
        require "alhena"
        raise ArgumentError, "layout cache capacity must be positive" unless capacity.is_a?(Integer) && capacity.positive?
        @font_db = provider(font_db, :font_db, %i[find fallback]) { FontDB.new }
        @shaper = provider(shaper, :shaper, [:shape]) { Shaper.new }
        @segmenter = provider(segmenter, :segmenter, [:grapheme_clusters]) { Unicode }
        @font, @capacity = font || @font_db.find, capacity
        @cache = {}
        @layout_lookup, @layout_keys = Array.new(9), {}
      end

      def layout_line(text, font: nil, size: 14, direction: :auto, features: {}, script: nil, language: nil, bidi: nil,
        writing_mode: :horizontal_tb)
        raise ArgumentError, "text must be valid UTF-8" unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
        raise ArgumentError, "font size must be finite and positive" unless size.is_a?(Numeric) && size.finite? && size.positive?
        raise ArgumentError, "direction must be auto, ltr, or rtl" unless %i[auto ltr rtl].include?(direction)
        raise ArgumentError, "writing mode must be horizontal_tb or vertical_rl" unless %i[horizontal_tb vertical_rl].include?(writing_mode)
        raise ArgumentError, "features must be a hash" unless features.is_a?(Hash)
        raise ArgumentError, "bidi must be a resolved line for this text" if bidi && (!bidi.is_a?(Unicode::Bidi::Result) || bidi.levels.length != text.length)
        font ||= @font
        features = features.empty? ? EMPTY_FEATURES : features.dup.freeze
        cached = cached_layout(text, font, size, direction, features, script, language, bidi, writing_mode)
        return cached if cached

        cache_bidi = bidi
        text = text.dup.freeze
        boundaries = grapheme_boundaries(text)
        if writing_mode == :vertical_rl
          glyphs = shape_glyphs(glyphs_for(text, font, size, vertical: true), text, size,
            direction: :ltr, features: features, script: script, language: language, writing_mode: writing_mode)
          scale = size.to_f / font.units_per_em
          line = LineLayout.new(text, glyphs.freeze, glyphs.sum(&:advance), font.ascent * scale,
            -font.descent * scale, size, carets_for(glyphs, boundaries).freeze, nil, writing_mode)
          return cache_layout(line, text, font, size, direction, features, script, language, cache_bidi, writing_mode)
        end
        bidi ||= text.ascii_only? && direction != :rtl ? nil : Unicode::Bidi.resolve(text, direction: direction)
        if bidi && (bidi.levels.any? { |level| level && level.odd? } || text.each_codepoint.any? { |point| Unicode::Bidi.control?(point) })
          line = bidi_line(text, font, size, boundaries, bidi, features, script, language)
          return cache_layout(line, text, font, size, direction, features, script, language, cache_bidi, writing_mode)
        end
        glyphs = shape_glyphs(glyphs_for(text, font, size), text, size,
          direction: :ltr, features: features, script: script, language: language)
        scale = size.to_f / font.units_per_em
        line = LineLayout.new(text, glyphs.freeze, glyphs.sum(&:advance), font.ascent * scale,
          -font.descent * scale, size, carets_for(glyphs, boundaries).freeze)
        cache_layout(line, text, font, size, direction, features, script, language, cache_bidi, writing_mode)
      end

      def layout_paragraph(text, **options)
        Paragraph.new(text, **options, typesetter: self)
      end

      # Copy only layout state, never a Renderer's atlases/rasterizer. Custom
      # providers explicitly deep-copy their state without mutating the source.
      def fork(capacity: @capacity)
        copies = []
        options = {font: @font, font_db: @font_db, shaper: @shaper, segmenter: @segmenter}.to_h do |kind, value|
          copy = layout_copy(kind, value)
          copies << copy unless copy.equal?(value)
          [kind, copy]
        end
        Typesetter.new(**options, capacity: capacity).tap { |copy| copy.instance_variable_set(:@owned_font, options[:font]) }
      rescue StandardError
        copies.reverse.uniq(&:object_id).each do |copy|
          copy.close if copy.respond_to?(:close)
        rescue StandardError
          nil # Preserve the original copy/validation error.
        end
        raise
      end

      def close
        return if @closed
        @closed = true
        @cache.clear
        @layout_keys.clear
        [@shaper, @segmenter, @font_db, @owned_font].uniq(&:object_id).each { |value| value.close if value.respond_to?(:close) }
      end

      private

      def cached_layout(text, font, size, direction, features, script, language, bidi, writing_mode)
        @layout_lookup[0] = text
        @layout_lookup[1] = font
        @layout_lookup[2] = size
        @layout_lookup[3] = direction
        @layout_lookup[4] = features
        @layout_lookup[5] = script
        @layout_lookup[6] = language
        @layout_lookup[7] = bidi
        @layout_lookup[8] = writing_mode
        return unless (cached = @cache.delete(@layout_lookup))
        @cache[@layout_keys.fetch(cached.object_id)] = cached
      end

      def grapheme_boundaries(text)
        characters = @segmenter.grapheme_clusters(text)
        raise Error, "segmenter must partition the UTF-8 text into nonempty strings" unless characters.is_a?(Array) && characters.all? { |part| part.is_a?(String) && !part.empty? && part.valid_encoding? } && characters.join == text
        boundaries, byte = [0], 0
        characters.each { |character| boundaries << (byte += character.bytesize) }
        boundaries
      end

      def glyphs_for(text, font, size, mirror: false, vertical: false)
        x, offset, glyphs = 0.0, 0, []
        text.each_char do |character|
          if Unicode::Bidi.control?(character.ord)
            offset += character.bytesize
            next
          end
          if (character.ord.between?(0xFE00, 0xFE0F) || character.ord.between?(0xE0100, 0xE01EF)) && !glyphs.empty?
            previous = glyphs.pop
            base = text.byteslice(previous.start, previous.finish - previous.start).each_char.first
            id = previous.font.glyph_id(base, variation_selector: character.ord)
            glyphs << Glyph.new(previous.font, id, previous.start, offset + character.bytesize, previous.x, previous.advance)
            offset += character.bytesize
            next
          end
          point = mirror ? Unicode::Bidi.mirrored(character.ord) : character.ord
          selected = @font_db.fallback(point, font)
          id = selected.glyph_id(point)
          advance = if vertical && selected.tables.key?("vmtx") && selected.tables.key?("vhea") &&
              selected.method(:advance).parameters.any? { |kind, name| name == :vertical && %i[key keyreq].include?(kind) }
            selected.advance(id, size: size, vertical: true)
          else
            selected.advance(id, size: size)
          end
          glyphs << Glyph.new(selected, id, offset, offset + character.bytesize, x, advance)
          x += advance
          offset += character.bytesize
        end
        glyphs
      end

      def shape_glyphs(glyphs, text, size, direction:, features:, script:, language:, writing_mode: :horizontal_tb)
        parameters = @shaper.method(:shape).parameters
        kwargs = {size: size, text: text, script: script, language: language,
          direction: direction, features: features, writing_mode: writing_mode}
        kwargs = kwargs.select { |key, _| parameters.include?([:key, key]) || parameters.include?([:keyreq, key]) } unless parameters.any? { |kind, _| kind == :keyrest }
        glyphs = @shaper.shape(glyphs, **kwargs)
        valid = glyphs.is_a?(Array) && glyphs.all? do |glyph|
          glyph.is_a?(Glyph) && glyph.start.is_a?(Integer) && glyph.finish.is_a?(Integer) &&
            glyph.start >= 0 && glyph.finish.between?(glyph.start + 1, text.bytesize) &&
            glyph.x.is_a?(Numeric) && glyph.x.finite? && glyph.advance.is_a?(Numeric) && glyph.advance.finite?
        end
        raise Error, "shaper must return finite Glyph values with valid UTF-8 byte ranges" unless valid
        unless direction == :ltr || kwargs.key?(:direction)
          x = 0.0
          glyphs = glyphs.reverse.map do |glyph|
            placed = glyph.with(x: x)
            x += glyph.advance
            placed
          end
        end
        glyphs
      end

      def bidi_line(text, font, size, boundaries, bidi, features, script, language)
        bytes = [0]
        text.each_char { |character| bytes << bytes.last + character.bytesize }
        runs = []
        bidi.visual_order.each do |index|
          level = bidi.levels[index]
          if runs.last && runs.last[0] == level && (runs.last[2] - index).abs == 1
            runs.last[2] = index
          else
            runs << [level, index, index]
          end
        end
        glyphs, visual_carets, x = [], [], 0.0
        runs.each do |level, first, last|
          lower, upper = [first, last].minmax
          part = text.byteslice(bytes[lower]...bytes[upper + 1])
          run_x = x
          shaped = shape_glyphs(glyphs_for(part, font, size, mirror: level.odd?), part, size,
            direction: level.odd? ? :rtl : :ltr, features: features, script: script, language: language)
          shaped.chunk { |glyph| [glyph.start, glyph.finish] }.each do |(start, finish), cluster|
            cluster_width = cluster.sum(&:advance)
            from, to = bytes[lower] + start, bytes[lower] + finish
            first_boundary = boundaries.bsearch_index { |boundary| boundary >= from } || boundaries.length
            last_boundary = boundaries.bsearch_index { |boundary| boundary > to } || boundaries.length
            offsets = boundaries[first_boundary...last_boundary]
            offsets = [from, to] if offsets.length < 2
            count = offsets.length - 1
            offsets.each_with_index do |offset, index|
              position = level.odd? ? x + cluster_width * (count - index) / count : x + cluster_width * index / count
              visual_carets << [offset, index == count ? :upstream : :downstream, position]
            end
            cluster.each { |glyph| glyphs << glyph.with(start: glyph.start + bytes[lower], finish: glyph.finish + bytes[lower], x: glyph.x + run_x) }
            x += cluster_width
          end
          if shaped.empty?
            visual_carets << [bytes[lower], :downstream, x]
            visual_carets << [bytes[upper + 1], :upstream, x]
          end
          (lower..upper).each do |index|
            next unless Unicode::Bidi.control?(text.byteslice(bytes[index]...bytes[index + 1]).ord)
            start, finish = bytes[index], bytes[index + 1]
            earlier = visual_carets.select { |byte, _, _| byte.between?(bytes[lower], start) }.max_by(&:first)
            position = earlier ? earlier.last : (level.odd? ? x : run_x)
            visual_carets << [start, :downstream, position]
            visual_carets << [finish, :upstream, position]
          end
        end
        visual_carets << [0, :downstream, 0.0] if visual_carets.empty?
        carets = boundaries.map do |byte|
          point = visual_carets.find { |offset, affinity, _| offset == byte && affinity == :downstream } ||
            visual_carets.find { |offset, _, _| offset == byte }
          [byte, point ? point.last : x]
        end
        scale = size.to_f / font.units_per_em
        LineLayout.new(text, glyphs.freeze, x, font.ascent * scale, -font.descent * scale,
          size, carets.freeze, visual_carets.sort_by(&:last).freeze)
      end

      def carets_for(glyphs, boundaries)
        carets, pen, boundary = [[0, 0.0]], 0.0, 1
        glyphs.chunk { |glyph| [glyph.start, glyph.finish] }.each do |(first, last), cluster|
          advance = cluster.sum(&:advance)
          first_boundary = boundary
          boundary += 1 while boundary < boundaries.length && boundaries[boundary] <= last
          count = boundary - first_boundary
          count.times do |index|
            carets << [boundaries[first_boundary + index], pen + advance * (index + 1) / count]
          end
          pen += advance
        end
        carets
      end

      def cache_layout(line, text, font, size, direction, features, script, language, bidi, writing_mode)
        @layout_keys.delete(@cache.shift.last.object_id) if @cache.length >= @capacity
        key = @layout_keys[line.object_id] = [text, font, size, direction, features, script, language, bidi, writing_mode].freeze
        @cache[key] = line
      end

      def layout_copy(kind, value)
        native = value.singleton_methods.empty?
        return Alhena::Font.new(value.data, index: value.index, axes: value.axis_values) if kind == :font && native && value.instance_of?(Alhena::Font)
        return FontDB.new(paths: value.paths) if kind == :font_db && native && value.instance_of?(FontDB)
        return Shaper.new if kind == :shaper && native && value.instance_of?(Shaper)
        return Unicode if kind == :segmenter && value.equal?(Unicode)
        raise CopyError, "#{kind} provider must implement #layout_copy for independent text layout" unless value.respond_to?(:layout_copy)
        copy = value.layout_copy
        methods = {font: %i[units_per_em ascent descent family glyph_id advance tables], font_db: %i[find fallback], shaper: [:shape], segmenter: [:grapheme_clusters]}.fetch(kind)
        unless !copy.equal?(value) && methods.all? { |name| copy.respond_to?(name) }
          copy.close if !copy.equal?(value) && copy.respond_to?(:close)
          raise CopyError, "#{kind} #layout_copy must return an independent provider responding to #{methods.join(', ')}"
        end
        copy
      rescue CopyError
        raise
      rescue StandardError => error
        raise CopyError, "#{kind} layout copy failed: #{error.message}"
      end

      def provider(value, kind, methods)
        return yield if value == :native
        raise ArgumentError, "unsupported #{kind} provider #{value.inspect}; use :native or an object responding to #{methods.join(', ')}" unless methods.all? { |name| value.respond_to?(name) }
        value
      end
    end
  end
end

require_relative "typesetter/copy_error"
