# frozen_string_literal: true

require "fiddle"
require "alhena"
require_relative "../../ffi/com"

module Zaniah
  module Platform
    module Windows
      # Rasterizes the same glyph IDs that the selected shaper produced. DirectWrite
      # owns the font face and glyph cache; Zaniah still owns layout and its atlas.
      class DirectWrite
        P, I, F = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_FLOAT
        FACTORY5_IID = [0x958db99a, 0xbe2a, 0x4f09].pack("L<S<S<") +
          [0xaf, 0x7d, 0x65, 0x18, 0x98, 0x03, 0xd1, 0xd3].pack("C8")
        MAX_PIXELS = 16_777_216

        def initialize(font_db: nil)
          raise Error, "DirectWrite is available only on Windows" unless RUBY_PLATFORM.match?(/mswin|mingw/)
          @font_db, @faces = font_db, {}.compare_by_identity
          @library = FFI::Library.new("dwrite.dll")
          output = pointer_out
          FFI::COM.check(@library.fn(:DWriteCreateFactory, [I, P, P], I).call(0, FACTORY5_IID, output))
          @factory = output.unpack1("J")
          raise Error, "DirectWrite factory unavailable" if @factory.zero?
        end

        def cache_key = "directwrite/#{RUBY_PLATFORM}/factory5"

        def rasterize(font, glyph, size:, subpixel_x: 0, antialias: :grayscale, **_options)
          raise IOError, "DirectWrite provider closed" unless @factory
          raise ArgumentError, "invalid font size" unless size.is_a?(Numeric) && size.finite? && size.positive?
          raise ArgumentError, "invalid glyph ID" unless glyph.is_a?(Integer) && glyph.between?(0, font.glyph_count - 1) && glyph <= 0xffff
          raise ArgumentError, "invalid subpixel position" unless subpixel_x.is_a?(Numeric) && subpixel_x.finite?
          raise ArgumentError, "antialias must be grayscale or cleartype" unless %i[grayscale cleartype].include?(antialias)
          # CreateFontFace selects a collection face, not a variable-font instance.
          # Preserve requested axes until a DirectWrite axis-aware face path exists.
          if font.respond_to?(:axis_values) && !font.axis_values.empty?
            return font.rasterize(glyph, size: size, subpixel_x: subpixel_x,
              lcd: antialias == :cleartype ? :rgb : nil)
          end

          face = native_face(font)
          index = [glyph].pack("S<")
          advance = [0.0].pack("e")
          run = [face, size.to_f, 1, Fiddle::Pointer[index].to_i,
            Fiddle::Pointer[advance].to_i, 0, 0, 0].pack("Q<eL<Q<Q<Q<L<L<")
          output = pointer_out
          FFI::COM.check(FFI::COM.vcall(@factory, 23, [P, F, P, I, I, F, F, P], I,
            run, 1.0, 0, 4, 0, subpixel_x.to_f, 0.0, output))
          analysis = output.unpack1("J")
          bounds = "\0".b * 16
          FFI::COM.check(FFI::COM.vcall(analysis, 3, [I, P], I, 1, bounds))
          left, top, right, bottom = bounds.unpack("l<4")
          width, height = right - left, bottom - top
          return Alhena::Bitmap.new(width: 0, height: 0, coverage: "") if width.zero? || height.zero?
          raise Error, "DirectWrite bitmap exceeds size limit" unless width.positive? && height.positive? && width * height <= MAX_PIXELS
          rgb = "\0".b * (width * height * 3)
          FFI::COM.check(FFI::COM.vcall(analysis, 4, [I, P, P, I], I, 1, bounds, rgb, rgb.bytesize))
          coverage = if antialias == :cleartype
            rgb
          else
            gray = "\0".b * (width * height)
            gray.bytesize.times do |index|
              offset = index * 3
              gray.setbyte(index, (rgb.getbyte(offset) + rgb.getbyte(offset + 1) + rgb.getbyte(offset + 2) + 1) / 3)
            end
            gray
          end
          Alhena::Bitmap.new(width: width, height: height, left: left, top: -top,
            channels: antialias == :cleartype ? 3 : 1, coverage: coverage)
        ensure
          FFI::COM.release(analysis) if analysis && !analysis.zero?
        end

        def close
          return unless @factory
          @faces.each_value { |face| FFI::COM.release(face) }
          @faces.clear
          if @memory_loader
            FFI::COM.check(FFI::COM.vcall(@factory, 14, [P], I, @memory_loader))
            FFI::COM.release(@memory_loader)
          end
          FFI::COM.release(@factory)
          @factory = nil
        end

        private

        def pointer_out = [0].pack("J")

        def native_face(font)
          @faces[font] ||= begin
            path = @font_db.path_for(font) if @font_db&.respond_to?(:path_for)
            path = nil if path && (!File.file?(path) || File.binread(path) != font.data)
            file = path ? file_from_path(path) : file_from_memory(font.data)
            supported, _file_type, face_type, count = analyze(file)
            raise Error, "DirectWrite cannot read font data" if supported.zero? || font.index >= count
            output = pointer_out
            files = [file].pack("J")
            FFI::COM.check(FFI::COM.vcall(@factory, 9, [I, I, P, I, I, P], I,
              face_type, 1, files, font.index, 0, output))
            output.unpack1("J")
          ensure
            FFI::COM.release(file) if file && !file.zero?
          end
        end

        def file_from_path(path)
          output = pointer_out
          wide = path.encode("UTF-16LE").b + "\0\0".b
          FFI::COM.check(FFI::COM.vcall(@factory, 7, [P, P, P], I, wide, 0, output))
          output.unpack1("J")
        end

        def file_from_memory(bytes)
          raise Error, "DirectWrite font data exceeds size limit" if bytes.bytesize > 0xffffffff
          unless @memory_loader
            output = pointer_out
            # Factory5 adds this method after 3 + 21 + 2 + 5 + 9 + 3 + 1 entries.
            FFI::COM.check(FFI::COM.vcall(@factory, 44, [P], I, output))
            loader = output.unpack1("J")
            begin
              FFI::COM.check(FFI::COM.vcall(@factory, 13, [P], I, loader))
              @memory_loader = loader
            rescue StandardError
              FFI::COM.release(loader) unless loader.zero?
              raise
            end
          end
          output = pointer_out
          # A null owner asks DirectWrite to copy bytes, so no Ruby object is pinned.
          FFI::COM.check(FFI::COM.vcall(@memory_loader, 4, [P, P, I, P, P], I,
            @factory, bytes, bytes.bytesize, 0, output))
          output.unpack1("J")
        end

        def analyze(file)
          supported, file_type, face_type, count = Array.new(4) { [0].pack("L<") }
          FFI::COM.check(FFI::COM.vcall(file, 5, [P, P, P, P], I,
            supported, file_type, face_type, count))
          [supported, file_type, face_type, count].map { |value| value.unpack1("L<") }
        end
      end
    end
  end
end
