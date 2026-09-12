# frozen_string_literal: true

require_relative "atlas"
require_relative "typesetter"

module Zaniah
  module TextSystem
    class Renderer < Typesetter
      MAX_PAINT_BYTES = 32 << 20

      attr_reader :atlas, :color_atlas, :cache_dir
      attr_accessor :scale_factor

      def initialize(font: nil, font_db: Zaniah.configuration.font_db, capacity: 2000, font_raster: Zaniah.configuration.font_raster,
        shaper: Zaniah.configuration.shaper, segmenter: Zaniah.configuration.segmenter, cache_dir: nil)
        super(font: font, font_db: font_db, capacity: capacity, shaper: shaper, segmenter: segmenter)
        @rasters = Alhena::Cache.new(capacity: 4096, max_bytes: 32 << 20)
        case font_raster
        when :native, :alhena
          # The default is the bundled pure-Ruby engine.
        when :core_text, :coretext
          require_relative "../platform/mac/core_text"
          @rasters = Platform::Mac::CoreText.new
        when :freetype
          require_relative "../platform/linux/free_type"
          @rasters = Platform::Linux::FreeType.new
        else
          raise ArgumentError, "unknown font rasterizer" unless font_raster.respond_to?(:rasterize)
          @rasters = font_raster
        end
        @atlas = Atlas.new
        @color_atlas, @color_rasters, @scale_factor = Atlas.new(format: :rgba8), {}, 1.0
        @paint_cache, @paint_colors, @paint_span_cache, @paint_bytes = {}, {}, {}, 0
        @paint_lookup = Array.new(6)
        if cache_dir
          raise ArgumentError, "cache_dir must be a nonempty path string" unless cache_dir.is_a?(String) && !cache_dir.empty? && !cache_dir.include?("\0")
          require_relative "atlas_cache"
          @cache_dir = File.expand_path(cache_dir).freeze
          @font_identities = {}.compare_by_identity
          @raster_identity = if [:native, :alhena].include?(font_raster)
            "alhena/#{Alhena::VERSION}"
          elsif @rasters.respond_to?(:cache_key) && (identity = @rasters.cache_key).is_a?(String) && !identity.empty?
            identity
          else
            raise ArgumentError, "disk-cached rasterizers must supply a stable nonempty String cache_key"
          end
        end
      end

      def paint_line(scene, line, x:, y:, color: "#ddd", spans: nil)
        scale = @scale_factor.to_f
        raise ArgumentError, "scale factor must be positive" unless scale.positive? && scale.finite?
        raise ArgumentError, "text origin must be finite" unless x.is_a?(Numeric) && x.finite? && y.is_a?(Numeric) && y.finite?
        color = paint_color(color)
        spans = paint_spans(spans)
        refresh_paint_cache
        @paint_lookup[0], @paint_lookup[1], @paint_lookup[2] = line.object_id, x, y
        @paint_lookup[3], @paint_lookup[4], @paint_lookup[5] = color, spans, scale
        cached = @paint_cache.delete(@paint_lookup)
        if cached
          @paint_cache[cached[3]] = cached
          batches = cached[1]
        else
          batches = pack_line(line, x, y, color, spans, scale)
          refresh_paint_cache
          length = batches.sum { |batch| batch.bytes.bytesize }
          if length <= MAX_PAINT_BYTES
            while !@paint_cache.empty? && (@paint_cache.length >= @capacity || @paint_bytes + length > MAX_PAINT_BYTES)
              @paint_bytes -= @paint_cache.shift.last[2]
            end
            # Retaining the line prevents object_id reuse while cached.
            key = [line.object_id, x, y, color, spans, scale].freeze
            @paint_cache[key] = [line, batches, length, key]
            @paint_bytes += length
          end
        end
        batches.each { |batch| scene.sprite_batch(batch) }
        scene
      end

      def paint_paragraph(scene, paragraph, x:, y:, color: "#ddd")
        paragraph.lines.each do |line|
          paint_line(scene, line.layout, x: x + line.x,
            y: y + line.y + (line.height - line.layout.ascent - line.layout.descent) / 2.0 + line.layout.ascent,
            color: color)
        end
        scene
      end

      def end_frame
        @atlas.end_frame
        @color_atlas.end_frame
      end

      def prewarm(text = (32..126).map(&:chr).join.force_encoding(Encoding::UTF_8), size: 14)
        scale = @scale_factor.to_f
        raise ArgumentError, "scale factor must be positive" unless scale.positive? && scale.finite?
        line = layout_line(text, size: size)
        if @cache_dir
          identity = [Zaniah::VERSION, Alhena::VERSION, @raster_identity, RUBY_PLATFORM, scale, size.to_f, text,
            line.glyphs.map { |glyph| [font_identity(glyph.font), glyph.id, glyph.x, glyph.advance] }]
          key = Digest::SHA256.hexdigest(JSON.generate(identity))
          mono, color = %w[mono color].map { |kind| File.join(@cache_dir, "#{key}-#{kind}.atlas") }
          mono_loaded, color_loaded = @atlas.load_cache(mono, key: key, preserve: true), @color_atlas.load_cache(color, key: key, preserve: true)
          if mono_loaded && color_loaded
            refresh_paint_cache
            return self
          end
        end
        tint = paint_color("#fff")
        4.times { |bucket| pack_line(line, bucket / (4.0 * scale), 0, tint, nil, scale) }
        if @cache_dir
          @atlas.save_cache(mono, key: key)
          @color_atlas.save_cache(color, key: key)
        end
        refresh_paint_cache
        self
      end

      def close
        return if @closed
        @paint_cache.clear
        @rasters.close if @rasters.respond_to?(:close) && ![@shaper, @segmenter, @font_db].include?(@rasters)
        super
      end

      private

      def font_identity(font)
        return font.object_id unless @cache_dir
        @font_identities[font] ||= begin
          raise ArgumentError, "disk-cached fonts must expose immutable data, index and axis_values" unless font.respond_to?(:data) && font.respond_to?(:index) && font.respond_to?(:axis_values) && font.data.is_a?(String) && font.data.frozen?
          digest = Digest::SHA256.new.update(font.data)
          digest.update(JSON.generate([font.index, font.axis_values.sort])).hexdigest.freeze
        end
      end

      def refresh_paint_cache
        return if @paint_mono_generation == @atlas.generation && @paint_color_generation == @color_atlas.generation
        @paint_cache.clear
        @paint_bytes = 0
        @paint_mono_generation, @paint_color_generation = @atlas.generation, @color_atlas.generation
      end

      def paint_color(value)
        return value if value.is_a?(Color)
        return Color.parse(value) if value.is_a?(Array)
        @paint_colors.clear if @paint_colors.length >= 256
        @paint_colors[value] ||= Color.parse(value)
      end

      def paint_spans(spans)
        return unless spans
        cached = @paint_span_cache[spans]
        return cached if cached
        @paint_span_cache.clear if @paint_span_cache.length >= 256
        # Keys are snapshots: callers may update their range/color arrays later.
        snapshot = spans.map do |first, last, tint|
          tint = tint.dup.freeze if tint.is_a?(String) || tint.is_a?(Array)
          [first, last, tint].freeze
        end.freeze
        @paint_span_cache[snapshot] = snapshot.map { |first, last, tint| [first, last, paint_color(tint)].freeze }.freeze
      end

      def pack_line(line, x, y, color, spans, scale)
        span_index, batches, values, texture = 0, [], [], nil
        line.glyphs.each do |glyph|
          span_index += 1 while spans && span_index < spans.length && glyph.start >= spans[span_index][1]
          tint = spans && spans[span_index] && glyph.start >= spans[span_index][0] ? spans[span_index][2] : color
          position = (x + glyph.x) * scale
          bucket = ((position - position.floor) * 4).round % 4
          key = [font_identity(glyph.font), glyph.id, (line.size * scale).to_f, bucket]
          colored = glyph.font.tables.key?("COLR") || glyph.font.tables.key?("sbix") || glyph.font.tables.key?("CBDT")
          entry = colored ? @color_atlas.lookup(key) : nil
          color_glyph = !entry.nil?
          bitmap = if colored && !entry
            unless @color_rasters.key?(key)
              @color_rasters.shift if @color_rasters.length >= 1024
              @color_rasters[key] = glyph.font.color_bitmap(glyph.id, size: line.size * scale, subpixel_x: bucket / 4.0)
            end
            @color_rasters[key]
          end
          if bitmap
            entry = @color_atlas.fetch(key) { bitmap }
            color_glyph = true
          end
          entry ||= @atlas.fetch(key) { @rasters.rasterize(glyph.font, glyph.id, size: line.size * scale, subpixel_x: bucket / 4.0) }
          next if entry.width.zero? || entry.height.zero?
          unless texture.equal?(entry.texture)
            batches << Scene::SpriteBatch.new(values.pack("f*").freeze, texture) unless values.empty?
            values.clear
            texture = entry.texture
          end
          tint = paint_color("#fff") if color_glyph
          values.push((position.floor + entry.left) / scale, ((y * scale).floor - entry.top) / scale, entry.width / scale, entry.height / scale,
            tint.r, tint.g, tint.b, tint.a, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            entry.x.to_f / texture.width, entry.y.to_f / texture.height,
            entry.width.to_f / texture.width, entry.height.to_f / texture.height,
            0, 0, 0, 0, 0, 0, 0, texture.format == :r8 ? 1 : 2,
            1, 0, 0, 1, 0, 0, 0, 0)
        end
        batches << Scene::SpriteBatch.new(values.pack("f*").freeze, texture) unless values.empty?
        batches.freeze
      end
    end
  end
end
