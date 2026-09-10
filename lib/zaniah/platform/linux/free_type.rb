# frozen_string_literal: true

require "fiddle/import"
require_relative "../../ffi/library"

module Zaniah
  module Platform
    module Linux
      class FreeType
        module Types
          extend Fiddle::Importer
          Face = struct ["long num_faces", "long face_index", "long face_flags", "long style_flags", "long num_glyphs", "void *family_name", "void *style_name", "int num_fixed_sizes", "void *available_sizes", "int num_charmaps", "void *charmaps", "void *generic_data", "void *generic_finalizer", "long bbox[4]", "unsigned short units_per_em", "short ascender", "short descender", "short height", "short max_advance_width", "short max_advance_height", "short underline_position", "short underline_thickness", "void *glyph", "void *size", "void *charmap"]
          Bitmap = struct ["unsigned int rows", "unsigned int width", "int pitch", "void *buffer", "unsigned short num_grays", "unsigned char pixel_mode", "unsigned char palette_mode", "void *palette"]
          Slot = struct ["void *library", "void *face", "void *next", "unsigned int glyph_index", "void *generic_data", "void *generic_finalizer", "long metrics[8]", "long linear_hori_advance", "long linear_vert_advance", "long advance[2]", "unsigned int format", {bitmap: Bitmap}, "int bitmap_left", "int bitmap_top"]
        end
        P, I, L, U = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_UINT
        def initialize
          require "alhena"
          @lib = FFI::Library.new("libfreetype.so.6", "/opt/homebrew/lib/libfreetype.6.dylib", "/usr/local/lib/libfreetype.6.dylib", "freetype.dll")
          pointer = [0].pack("J")
          check(@lib.fn(:FT_Init_FreeType, [P], I).call(pointer))
          @library, @faces = pointer.unpack1("J"), {}
        end
        def cache_key
          raise IOError, "FreeType provider closed" unless @library
          @cache_key ||= begin
            major, minor, patch = [0].pack("i"), [0].pack("i"), [0].pack("i")
            @lib.fn(:FT_Library_Version, [P, P, P, P], Fiddle::TYPE_VOID).call(@library, major, minor, patch)
            "freetype/#{RUBY_PLATFORM}/#{[major, minor, patch].map { |value| value.unpack1('i') }.join('.')}".freeze
          end
        end
        def rasterize(font, glyph, size:, subpixel_x: 0, hinting: false, **_options)
          raise IOError, "FreeType provider closed" unless @library
          raise ArgumentError, "invalid font size" unless size.is_a?(Numeric) && size.finite? && size.positive?
          raise ArgumentError, "invalid glyph ID" unless glyph.is_a?(Integer) && glyph.between?(0, font.glyph_count - 1)
          raise ArgumentError, "invalid subpixel position" unless subpixel_x.is_a?(Numeric) && subpixel_x.finite?
          face = @faces[font] ||= begin
            pointer = [0].pack("J")
            check(@lib.fn(:FT_New_Memory_Face, [P, P, L, L, P], I).call(@library, font.data, font.data.bytesize, font.index, pointer))
            handle = pointer.unpack1("J")
            unless font.axis_values.empty?
              coordinates = font.axes.map { |tag, axis| (font.axis_values.fetch(tag, axis[:default]).clamp(axis[:min], axis[:max]) * 65_536).round }.pack("l!*")
              check(@lib.fn(:FT_Set_Var_Design_Coordinates, [P, U, P], I).call(handle, font.axes.length, coordinates))
            end
            handle
          end
          check(@lib.fn(:FT_Set_Char_Size, [P, L, L, U, U], I).call(face, 0, (size * 64).round, 72, 72))
          delta = [(subpixel_x * 64).round, 0].pack("l!2")
          @lib.fn(:FT_Set_Transform, [P, P, P], Fiddle::TYPE_VOID).call(face, 0, delta)
          check(@lib.fn(:FT_Load_Glyph, [P, U, I], I).call(face, glyph, 4 | 8 | (hinting ? 0 : 2)))
          slot = Types::Slot.new(Types::Face.new(Fiddle::Pointer.new(face)).glyph)
          bitmap = slot.bitmap
          raise Error, "FreeType bitmap exceeds size limit" if bitmap.width * bitmap.rows > 16_777_216
          bytes = String.new(capacity: bitmap.width * bitmap.rows, encoding: Encoding::BINARY)
          bitmap.rows.times do |row|
            pointer = Fiddle::Pointer.new(bitmap.buffer.to_i + row * bitmap.pitch)
            case bitmap.pixel_mode
            when 2 then bytes << pointer[0, bitmap.width]
            when 1
              packed = pointer[0, (bitmap.width + 7) / 8]
              bitmap.width.times { |column| bytes << ((packed.getbyte(column / 8) & (0x80 >> (column % 8))).zero? ? 0 : 255) }
            else raise Error, "unsupported FreeType coverage mode #{bitmap.pixel_mode}"
            end
          end
          Alhena::Bitmap.new(width: bitmap.width, height: bitmap.rows, left: slot.bitmap_left, top: slot.bitmap_top, coverage: bytes)
        end
        def check(code)
          raise Error, "FreeType error #{code}" unless code.zero?
        end
        def close
          return unless @library
          @faces.each_value { |face| @lib.fn(:FT_Done_Face, [P], I).call(face) }
          @faces.clear
          @lib.fn(:FT_Done_FreeType, [P], I).call(@library)
          @library = nil
        end
      end
    end
  end
end
