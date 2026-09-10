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
        @layout_lookup, @layout_keys = [nil, nil, nil], {}
      end

      def layout_line(text, font: nil, size: 14)
        raise ArgumentError, "text must be valid UTF-8" unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
        raise ArgumentError, "font size must be finite and positive" unless size.is_a?(Numeric) && size.finite? && size.positive?
        font ||= @font
        cached = cached_layout(text, font, size)
        return cached if cached

        text = text.dup.freeze
        boundaries = grapheme_boundaries(text)
        glyphs = shape_glyphs(glyphs_for(text, font, size), text, size)
        scale = size.to_f / font.units_per_em
        line = LineLayout.new(text, glyphs.freeze, glyphs.sum(&:advance), font.ascent * scale,
          -font.descent * scale, size, carets_for(glyphs, boundaries).freeze)
        cache_layout(line, text, font, size)
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

      def cached_layout(text, font, size)
        @layout_lookup[0], @layout_lookup[1], @layout_lookup[2] = text, font, size
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

      def glyphs_for(text, font, size)
        x, offset, glyphs = 0.0, 0, []
        text.each_char do |character|
          if (character.ord.between?(0xFE00, 0xFE0F) || character.ord.between?(0xE0100, 0xE01EF)) && !glyphs.empty?
            previous = glyphs.pop
            base = text.byteslice(previous.start, previous.finish - previous.start).each_char.first
            id = previous.font.glyph_id(base, variation_selector: character.ord)
            glyphs << Glyph.new(previous.font, id, previous.start, offset + character.bytesize, previous.x, previous.advance)
            offset += character.bytesize
            next
          end
          selected = @font_db.fallback(character.ord, font)
          id = selected.glyph_id(character)
          advance = selected.advance(id, size: size)
          glyphs << Glyph.new(selected, id, offset, offset + character.bytesize, x, advance)
          x += advance
          offset += character.bytesize
        end
        glyphs
      end

      def shape_glyphs(glyphs, text, size)
        glyphs = @shaper.shape(glyphs, size: size, text: text)
        valid = glyphs.is_a?(Array) && glyphs.all? do |glyph|
          glyph.is_a?(Glyph) && glyph.start.is_a?(Integer) && glyph.finish.is_a?(Integer) &&
            glyph.start >= 0 && glyph.finish.between?(glyph.start + 1, text.bytesize) &&
            glyph.x.is_a?(Numeric) && glyph.x.finite? && glyph.advance.is_a?(Numeric) && glyph.advance.finite?
        end
        raise Error, "shaper must return finite Glyph values with valid UTF-8 byte ranges" unless valid
        glyphs
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

      def cache_layout(line, text, font, size)
        @layout_keys.delete(@cache.shift.last.object_id) if @cache.length >= @capacity
        key = @layout_keys[line.object_id] = [text, font, size].freeze
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
