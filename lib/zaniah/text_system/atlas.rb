# frozen_string_literal: true

module Zaniah
  module TextSystem
    class Atlas
      attr_reader :generation, :texture

      def initialize(width: 2048, height: 2048, format: :r8)
        @width, @height, @format = width, height, format
        @generation, @cache, @retired = 0, {}, []
        reset
      end

      def fetch(key)
        return @cache[key] if @cache.key?(key)
        bitmap = yield
        raise Error, "glyph exceeds atlas dimensions" if bitmap.width + 2 > @width || bitmap.height + 2 > @height
        position = allocate(bitmap.width + 2, bitmap.height + 2)
        unless position
          @retired << @texture
          reset
          position = allocate(bitmap.width + 2, bitmap.height + 2)
        end
        x, y = position.map { |value| value + 1 }
        @texture.upload(x, y, bitmap.width, bitmap.height, @format == :rgba8 ? bitmap.rgba : bitmap.coverage)
        @cache[key] = Entry.new(@texture, x, y, bitmap.width, bitmap.height, bitmap.left, bitmap.top)
      end

      def lookup(key) = @cache[key]
      def end_frame = @retired.clear

      def save_cache(path, key:)
        require_relative "atlas_cache"
        AtlasCache.save(path, key: key, texture: @texture, skyline: @skyline, entries: @cache)
      end

      def load_cache(path, key:, preserve: false)
        require_relative "atlas_cache"
        loaded = AtlasCache.load(path, key: key, width: @width, height: @height, format: @format)
        return false unless loaded
        return false if preserve && @cache.any? { |id, _| !loaded.last.key?(id) }
        @retired << @texture
        @texture, @skyline, @cache = loaded
        @generation += 1
        true
      end

      private

      def reset
        @texture = GPU::Texture.new(@width, @height, format: @format)
        @skyline = [[0, 0, @width]]
        @cache.clear
        @generation += 1
      end

      def allocate(width, height)
        choice = nil
        @skyline.each_index do |index|
          x, y, = @skyline[index]
          next if x + width > @width
          remaining, cursor = width, index
          while remaining.positive? && cursor < @skyline.length
            y = [y, @skyline[cursor][1]].max
            break if y + height > @height
            remaining -= @skyline[cursor][2]
            cursor += 1
          end
          next if remaining.positive? || y + height > @height
          choice = [x, y, index] if choice.nil? || y < choice[1] || (y == choice[1] && x < choice[0])
        end
        return unless choice
        x, y, index = choice
        @skyline.insert(index, [x, y + height, width])
        cursor = index + 1
        while cursor < @skyline.length
          previous, current = @skyline[cursor - 1], @skyline[cursor]
          overlap = previous[0] + previous[2] - current[0]
          break if overlap <= 0
          if current[2] <= overlap
            @skyline.delete_at(cursor)
          else
            current[0] += overlap
            current[2] -= overlap
            break
          end
        end
        cursor = 0
        while cursor + 1 < @skyline.length
          if @skyline[cursor][1] == @skyline[cursor + 1][1]
            @skyline[cursor][2] += @skyline.delete_at(cursor + 1)[2]
          else
            cursor += 1
          end
        end
        [x, y]
      end
    end
  end
end

require_relative "atlas/entry"
