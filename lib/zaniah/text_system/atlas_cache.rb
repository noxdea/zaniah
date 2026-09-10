# frozen_string_literal: true

require "digest"
require "json"
require "tempfile"
require "fileutils"

module Zaniah
  module TextSystem
    # A bounded JSON manifest plus raw occupied texture rows. No Ruby objects are
    # deserialized, and no texture allocation happens until every bound is checked.
    module AtlasCache
      MAGIC = "TSATLAS\0".b.freeze
      VERSION = 1
      HEADER_BYTES = 52
      MAX_METADATA = 2 << 20
      MAX_PIXELS = 32 << 20
      MAX_ENTRIES = 16_384
      WINDOWS = RUBY_PLATFORM.match?(/mingw|mswin/)

      def self.save(path, key:, texture:, skyline:, entries:)
        path = safe_path(path, create: true)
        return false unless path
        rows = skyline.map { |_, y, _| y }.max || 0
        records = entries.map { |id, entry| [id, entry.x, entry.y, entry.width, entry.height, entry.left, entry.top] }
        metadata = {"key" => key, "width" => texture.width, "height" => texture.height,
          "format" => texture.format.to_s, "rows" => rows, "skyline" => skyline, "entries" => records}
        return false unless valid_metadata?(metadata, key: key, width: texture.width, height: texture.height, format: texture.format)
        json = JSON.generate(metadata)
        return false if json.bytesize > MAX_METADATA
        pixels = texture.data.byteslice(0, texture.width * rows * (texture.format == :r8 ? 1 : 4))
        digest = Digest::SHA256.new.update(json).update(pixels).digest
        header = MAGIC + [VERSION, json.bytesize, pixels.bytesize].pack("N3") + digest
        Tempfile.create([".zaniah-atlas-", ".tmp"], File.dirname(path)) do |file|
          file.binmode
          file.write(header)
          file.write(json)
          file.write(pixels)
          file.flush
          file.fsync
          file.close
          attempts = 0
          begin
            File.rename(file.path, path)
          rescue Errno::EACCES, Errno::EEXIST
            raise unless WINDOWS && (attempts += 1) <= 10
            sleep(0.001 * attempts)
            retry
          end
        end
        true
      rescue SystemCallError, IOError, JSON::GeneratorError
        false
      end

      def self.load(path, key:, width:, height:, format:)
        path = safe_path(path, create: false)
        return unless path
        flags = File::RDONLY
        flags |= File::NOFOLLOW if defined?(File::NOFOLLOW) && !WINDOWS
        File.open(path, flags) do |file|
          file.binmode
          stat, location = file.stat, File.lstat(path)
          return unless stat.file? && location.file?
          return unless WINDOWS || (stat.ino == location.ino && stat.dev == location.dev)
          return unless stat.size.between?(HEADER_BYTES, HEADER_BYTES + MAX_METADATA + MAX_PIXELS)
          header = file.read(HEADER_BYTES)
          return unless header&.bytesize == HEADER_BYTES && header.byteslice(0, 8) == MAGIC
          version, json_size, pixel_size = header.byteslice(8, 12).unpack("N3")
          return unless version == VERSION && json_size.between?(2, MAX_METADATA) && pixel_size <= MAX_PIXELS
          return unless stat.size == HEADER_BYTES + json_size + pixel_size
          json, pixels = file.read(json_size), file.read(pixel_size)
          return unless json&.bytesize == json_size && pixels&.bytesize == pixel_size
          return unless Digest::SHA256.new.update(json).update(pixels).digest == header.byteslice(20, 32)
          metadata = JSON.parse(json, max_nesting: 8, create_additions: false)
          return unless valid_metadata?(metadata, key: key, width: width, height: height, format: format)
          return unless pixels.bytesize == width * metadata["rows"] * (format == :r8 ? 1 : 4)
          texture = GPU::Texture.new(width, height, format: format)
          texture.upload(0, 0, width, metadata["rows"], pixels)
          entries = metadata["entries"].to_h do |id, x, y, w, h, left, top|
            [id.freeze, Atlas::Entry.new(texture, x, y, w, h, left, top)]
          end
          [texture, metadata["skyline"], entries]
        end
      rescue SystemCallError, IOError, JSON::ParserError, EncodingError
        nil
      end

      def self.safe_path(path, create:)
        raise ArgumentError, "atlas cache path must be a nonempty string" unless path.is_a?(String) && !path.empty? && !path.include?("\0")
        path = File.expand_path(path)
        directory = File.dirname(path)
        return if File.symlink?(directory) || File.symlink?(path)
        FileUtils.mkdir_p(directory, mode: 0o700) if create && !File.exist?(directory)
        return unless File.directory?(directory)
        File.join(File.realpath(directory), File.basename(path))
      end

      def self.valid_metadata?(data, key:, width:, height:, format:)
        return false unless data.is_a?(Hash) && data["key"] == key && key.is_a?(String) && key.bytesize.between?(1, 4096)
        return false unless data["width"] == width && data["height"] == height && data["format"] == format.to_s
        return false unless width.is_a?(Integer) && height.is_a?(Integer) && width.between?(1, 8192) && height.between?(1, 8192)
        return false unless [:r8, :rgba8].include?(format) && width * height * (format == :r8 ? 1 : 4) <= MAX_PIXELS
        rows, skyline, entries = data.values_at("rows", "skyline", "entries")
        return false unless rows.is_a?(Integer) && rows.between?(0, height) && skyline.is_a?(Array) && skyline.length.between?(1, width)
        return false unless entries.is_a?(Array) && entries.length <= MAX_ENTRIES
        cursor, highest = 0, 0
        skyline.each do |segment|
          return false unless segment.is_a?(Array) && segment.length == 3 && segment.all? { |value| value.is_a?(Integer) }
          x, y, span = segment
          return false unless x == cursor && y.between?(0, rows) && span.positive? && x + span <= width
          cursor += span
          highest = y if y > highest
        end
        return false unless cursor == width && highest == rows
        seen, area = {}, 0
        entries.each do |record|
          return false unless record.is_a?(Array) && record.length == 7
          id, x, y, w, h, left, top = record
          return false unless valid_id?(id) && !seen.key?(id)
          seen[id] = true
          return false unless [x, y, w, h, left, top].all? { |value| value.is_a?(Integer) }
          return false unless x >= 1 && y >= 1 && w >= 0 && h >= 0 && x + w + 1 <= width && y + h + 1 <= rows
          return false unless left.abs <= 1_000_000 && top.abs <= 1_000_000
          area += (w + 2) * (h + 2)
          return false if area > width * rows
          # Restored skyline allocation must not overwrite an existing glyph.
          cursor = skyline.bsearch_index { |sx, _, sw| sx + sw > x - 1 }
          while cursor && cursor < skyline.length && skyline[cursor][0] < x + w + 1
            return false if skyline[cursor][1] < y + h + 1
            cursor += 1
          end
        end
        true
      end

      def self.valid_id?(id)
        return false unless id.is_a?(Array) && id.length == 4
        font, glyph, size, bucket = id
        font.is_a?(String) && font.match?(/\A[0-9a-f]{64}\z/) && glyph.is_a?(Integer) && glyph.between?(0, 0xffffffff) &&
          size.is_a?(Numeric) && size.finite? && size.positive? && size <= 16_384 && bucket.is_a?(Integer) && bucket.between?(0, 3)
      end
      private_class_method :safe_path, :valid_metadata?, :valid_id?
    end
  end
end
