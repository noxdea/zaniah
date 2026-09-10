# frozen_string_literal: true

require "alhena"

module Zaniah
  module TextSystem
    # Reads directories and small metadata tables, never outlines during discovery.
    class FontDB
      PREFERRED = %w[Menlo DejaVu\ Sans\ Mono Consolas Liberation\ Mono Noto\ Sans\ Mono].freeze
      MAX_TABLE = 8 << 20
      attr_reader :paths

      def initialize(paths: nil)
        roots = if RUBY_PLATFORM.include?("darwin")
          ["/System/Library/Fonts", "/Library/Fonts", File.expand_path("~/Library/Fonts")]
        elsif RUBY_PLATFORM.match?(/mswin|mingw/)
          [File.join(ENV.fetch("WINDIR", "C:/Windows"), "Fonts")]
        else
          ["/usr/share/fonts", "/usr/local/share/fonts", File.expand_path("~/.local/share/fonts"), File.expand_path("~/.fonts")]
        end
        paths ||= roots.flat_map { |root| Dir[File.join(root, "**", "*.{ttf,otf,ttc,otc,TTF,OTF,TTC,OTC}")] }
        raise ArgumentError, "font paths must be an array" unless paths.is_a?(Array) && paths.all? { |path| path.is_a?(String) && !path.include?("\0") }
        @paths = paths.map { |path| File.expand_path(path) }.uniq.freeze
        refresh
      end

      def refresh
        @faces, @fonts, @data, @fallback, @probes, @matches, @normalized = nil, {}, {}, {}, {}, {}, {}
        self
      end

      def faces
        @faces ||= @paths.flat_map do |path|
          File.open(path, "rb") do |io|
            header = read(io, 0, 12)
            offsets = if header.bytes(0, 4) == "ttcf"
              raise Error, "unsupported font collection version" unless [0x10000, 0x20000].include?(header.u32(4))
              count = header.u32(8)
              raise Error, "font collection exceeds face limit" unless count.between?(1, 4096)
              read(io, 12, count * 4).data.unpack("N*")
            else
              [0]
            end
            offsets.each_with_index.filter_map do |offset, index|
              metadata(io, path, offset, index)
            rescue Error, Alhena::Error, EncodingError, ArgumentError
              nil
            end
          end
        rescue SystemCallError, IOError, Error, Alhena::Error
          []
        end.freeze
      end

      def open(path, index: 0)
        path = File.expand_path(path)
        @fonts[[path, index]] ||= Alhena::Font.new(@data[path] ||= File.binread(path).freeze, index: index)
      end

      def find(family: nil, weight: 400, width: 5, style: :normal)
        raise ArgumentError, "family must be a string" unless family.nil? || family.is_a?(String)
        raise ArgumentError, "weight must be in 1..1000" unless weight.is_a?(Integer) && weight.between?(1, 1000)
        raise ArgumentError, "width must be an OS/2 class in 1..9" unless width.is_a?(Integer) && width.between?(1, 9)
        raise ArgumentError, "style must be normal, italic or oblique" unless %i[normal italic oblique].include?(style)
        key = [family && normalize(family), weight, width, style]
        @matches[key] ||= begin
          requested = key[0]
          candidates = requested ? faces.select { |face| face.families.any? { |name| normalize(name) == requested } } : []
          candidates = faces if candidates.empty?
          candidates.sort_by do |face|
            family_rank = if requested && face.families.any? { |name| normalize(name) == requested }
              0
            else
              PREFERRED.index { |name| face.families.any? { |alias_name| normalize(alias_name) == normalize(name) } } || (face.fixed_pitch ? PREFERRED.length : PREFERRED.length + 1)
            end
            [family_rank, width_rank(face.width, width), style_rank(face.style, style), weight_rank(face.weight, weight), face.path, face.index]
          end.each do |face|
            begin
              font = open(face.path, index: face.index)
              # Reject incomplete/corrupt sfnts here, before handing one to layout.
              font.units_per_em
              font.ascent
              font.glyph_id(32)
              break font
            rescue Alhena::Error, SystemCallError, IOError
              next
            end
          end.then do |found|
            found.is_a?(Alhena::Font) ? found : bundled_font
          end
        end
      end

      def fallback(codepoint, primary)
        return primary unless primary.glyph_id(codepoint).zero?
        @fallback[[primary, codepoint]] ||= begin
          found = faces.find do |face|
            probe = @probes[[face.path, face.index]] ||= probe_font(face)
            !probe.glyph_id(codepoint).zero?
          rescue Error, Alhena::Error, SystemCallError, IOError
            false
          end
          found ? open(found.path, index: found.index) : primary
        end
      end

      private

      def normalize(name) = @normalized[name] ||= name.unicode_normalize(:nfkc).downcase(:fold).gsub(/\s+/, " ").strip.freeze
      def width_rank(actual, wanted)
        wanted <= 5 ? [actual > wanted ? 1 : 0, (actual - wanted).abs] : [actual < wanted ? 1 : 0, (actual - wanted).abs]
      end
      def style_rank(actual, wanted)
        {normal: %i[normal oblique italic], italic: %i[italic oblique normal], oblique: %i[oblique italic normal]}.fetch(wanted).index(actual)
      end
      def weight_rank(actual, wanted)
        if wanted.between?(400, 500)
          actual.between?(wanted, 500) ? [0, actual - wanted] : actual < wanted ? [1, wanted - actual] : [2, actual - 500]
        else
          preferred = wanted < 400 ? actual <= wanted : actual >= wanted
          [preferred ? 0 : 1, (actual - wanted).abs]
        end
      end
      def bundled_font
        path = File.expand_path("../../../assets/fonts/Abel-Regular.ttf", __dir__)
        raise Error, "no readable TrueType/OpenType font found" unless File.file?(path)
        open(path)
      end
      def read(io, offset, length)
        raise Error, "font metadata outside size limit" unless offset >= 0 && length >= 0 && length <= MAX_TABLE
        io.seek(offset)
        bytes = io.read(length)
        raise Error, "truncated font metadata" unless bytes && bytes.bytesize == length
        Alhena::Binary.new(bytes)
      end
      def metadata(io, path, offset, index)
        header = read(io, offset, 12)
        raise Error, "not an sfnt font" unless ["\x00\x01\x00\x00".b, "OTTO", "true"].include?(header.bytes(0, 4))
        count = header.u16(4)
        raise Error, "invalid sfnt table count" unless count.between?(1, 4096)
        directory = read(io, offset + 12, count * 16)
        size = io.stat.size
        tables = count.times.to_h do |i|
          at = i * 16
          tag, start, length = directory.bytes(at, 4), directory.u32(at + 8), directory.u32(at + 12)
          raise Error, "sfnt table outside file" if start > size - length
          [tag, [start, length].freeze]
        end
        raise Error, "duplicate sfnt tables" unless tables.length == count
        names = family_names(read(io, *tables.fetch("name")))
        raise Error, "font has no family name" if names.empty?
        os2 = tables["OS/2"] && read(io, tables["OS/2"][0], [tables["OS/2"][1], 64].min)
        weight, width = os2 ? [os2.u16(4), os2.u16(6)] : [400, 5]
        weight, width = 400, 5 unless weight.between?(1, 1000) && width.between?(1, 9)
        post = tables["post"] && read(io, tables["post"][0], [tables["post"][1], 16].min)
        flags = os2 && os2.size >= 64 ? os2.u16(62) : 0
        style = flags & 512 != 0 ? :oblique : flags & 1 != 0 || (post && post.i32(4) != 0) ? :italic : :normal
        Face.new(path, index, names.first, names.freeze, weight, width, style, !!(post && post.u32(12) != 0), tables.freeze)
      rescue KeyError
        raise Error, "missing font metadata table"
      end
      def family_names(data)
        count, storage = data.u16(2), data.u16(4)
        data.check(6, count * 12)
        count.times.filter_map do |i|
          platform, encoding, language, id, length, offset = data.bytes(6 + i * 12, 12).unpack("n6")
          next unless [1, 16, 21].include?(id) && ([0, 3].include?(platform) || (platform == 1 && encoding.zero?))
          text = data.bytes(storage + offset, length).force_encoding(platform == 1 ? "macRoman" : "UTF-16BE").encode("UTF-8")
          next if text.empty?
          [id == 16 ? 0 : id == 1 ? 1 : 2, platform == 3 && language == 0x409 ? 0 : 1, text.freeze]
        end.sort_by { |priority, language, _| [priority, language] }.map(&:last).uniq
      end
      def probe_font(face)
        tables = File.open(face.path, "rb") do |io|
          %w[cmap maxp].to_h { |tag| [tag, read(io, *face.tables.fetch(tag)).data] }
        end
        # Reuse Alhena's checked cmap 0/4/6/12/13 parser on a tiny sfnt;
        # no glyph outlines or full collection blobs are loaded for misses.
        offset, directory, payload = 12 + tables.length * 16, "".b, "".b
        tables.each do |tag, bytes|
          directory << [tag, 0, offset, bytes.bytesize].pack("a4N3")
          payload << bytes
          offset += bytes.bytesize
        end
        Alhena::Font.new([0x10000, tables.length, 0, 0, 0].pack("Nn4") + directory + payload)
      rescue KeyError
        raise Error, "font has no Unicode cmap"
      end
    end
  end
end

require_relative "font_db/face"
