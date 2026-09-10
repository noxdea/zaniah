# frozen_string_literal: true

require_relative "../../ffi/struct"

module Zaniah
  module Platform
    module Mac
      class CoreText
        P, L, D, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_VOID
        def initialize
          require "alhena"
          @cf = FFI::Library.new("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
          @ct = FFI::Library.new("/System/Library/Frameworks/CoreText.framework/CoreText")
          @cg = FFI::Library.new("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
          @descriptors, @fonts = {}, {}
          @bounds = FFI::Struct::Signature.new([:pointer], :rect)
        end
        def cache_key
          require "etc"
          @cache_key ||= "coretext/#{RUBY_PLATFORM}/#{Etc.uname.values_at(:release, :version).join('/')}".freeze
        end
        def native_font(font, size)
          @fonts[[font, size]] ||= begin
            descriptor = @descriptors[font] ||= begin
              bytes = font.data
              data = @cf.fn(:CFDataCreate, [P, P, L], P).call(0, bytes, bytes.bytesize)
              list = @ct.fn(:CTFontManagerCreateFontDescriptorsFromData, [P], P).call(data)
              raise Error, "CoreText cannot read font data" if list.null?
              count = @cf.fn(:CFArrayGetCount, [P], L).call(list)
              raise Error, "CoreText font collection index out of range" unless font.index < count
              item = @cf.fn(:CFArrayGetValueAtIndex, [P, L], P).call(list, font.index)
              item = @cf.fn(:CFRetain, [P], P).call(item)
              @cf.fn(:CFRelease, [P], V).call(list)
              @cf.fn(:CFRelease, [P], V).call(data)
              item
            end
            handle = @ct.fn(:CTFontCreateWithFontDescriptor, [P, D, P], P).call(descriptor, size, 0)
            font.axis_values.empty? ? handle : varied_font(handle, font.axis_values)
          end
        end
        def varied_font(handle, axes)
          descriptor = @ct.fn(:CTFontCopyFontDescriptor, [P], P).call(handle)
          axes.each do |tag, value|
            key = @cf.fn(:CFNumberCreate, [P, Fiddle::TYPE_INT, P], P).call(0, 3, [tag.unpack1("N")].pack("i"))
            next_descriptor = @ct.fn(:CTFontDescriptorCreateCopyWithVariation, [P, P, D], P).call(descriptor, key, value)
            @cf.fn(:CFRelease, [P], V).call(key)
            @cf.fn(:CFRelease, [P], V).call(descriptor)
            descriptor = next_descriptor
          end
          result = @ct.fn(:CTFontCreateCopyWithAttributes, [P, D, P, P], P).call(handle, 0, 0, descriptor)
          raise Error, "CoreText rejected font variations" if result.null?
          result
        ensure
          @cf.fn(:CFRelease, [P], V).call(handle)
          @cf.fn(:CFRelease, [P], V).call(descriptor) if descriptor
        end
        def rasterize(font, glyph, size:, subpixel_x: 0, **_options)
          raise ArgumentError, "invalid font size" unless size.is_a?(Numeric) && size.finite? && size.positive?
          raise ArgumentError, "invalid glyph ID" unless glyph.is_a?(Integer) && glyph.between?(0, font.glyph_count - 1)
          raise ArgumentError, "invalid subpixel position" unless subpixel_x.is_a?(Numeric) && subpixel_x.finite?
          handle = native_font(font, size)
          path = @ct.fn(:CTFontCreatePathForGlyph, [P, Fiddle::TYPE_USHORT, P], P).call(handle, glyph, 0)
          return Alhena::Bitmap.new(width: 0, height: 0, coverage: "") if path.null?
          x, y, width, height = @bounds.call(@cg.handle["CGPathGetBoundingBox"], path)
          left, bottom = (x + subpixel_x).floor, y.floor
          right, top = (x + width + subpixel_x).ceil, (y + height).ceil
          width, height = right - left, top - bottom
          return Alhena::Bitmap.new(width: 0, height: 0, coverage: "") if width.zero? || height.zero?
          raise Error, "CoreText bitmap exceeds size limit" if width * height > 16_777_216
          bytes = "\0".b * (width * height)
          context = @cg.fn(:CGBitmapContextCreate, [P, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_SIZE_T, P, Fiddle::TYPE_UINT], P).call(bytes, width, height, 8, width, 0, 7)
          raise Error, "CoreGraphics alpha bitmap context unavailable" if context.null?
          @cg.fn(:CGContextSetShouldAntialias, [P, Fiddle::TYPE_BOOL], V).call(context, 1)
          @cg.fn(:CGContextSetGrayFillColor, [P, D, D], V).call(context, 1, 1)
          @cg.fn(:CGContextTranslateCTM, [P, D, D], V).call(context, -left + subpixel_x, -bottom)
          # Filling the CoreText outline avoids CTFontDrawGlyphs pixel snapping
          # and preserves the requested fractional position in an R8 context.
          @cg.fn(:CGContextAddPath, [P, P], V).call(context, path)
          @cg.fn(:CGContextFillPath, [P], V).call(context)
          Alhena::Bitmap.new(width: width, height: height, left: left, top: top, coverage: bytes)
        ensure
          @cg.fn(:CGContextRelease, [P], V).call(context) if context && !context.null?
          @cg.fn(:CGPathRelease, [P], V).call(path) if path && !path.null?
        end
        def close
          @fonts.each_value { |font| @cf.fn(:CFRelease, [P], V).call(font) }
          @descriptors.each_value { |descriptor| @cf.fn(:CFRelease, [P], V).call(descriptor) }
          @fonts.clear
          @descriptors.clear
        end
      end
    end
  end
end
