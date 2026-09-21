# frozen_string_literal: true

module Zaniah
  # Small, dependency-free GIF87a/GIF89a decoder. Frames are returned as RGBA
  # snapshots so callers can choose whether to animate or keep the first frame.
  module GIF
    Frame = Data.define(:pixels, :delay, :disposal)
    module_function

    def decode(bytes, max_pixels: 16_777_216)
      raise ArgumentError, "not a GIF" unless bytes.start_with?("GIF87a", "GIF89a")
      reader = Reader.new(bytes)
      reader.skip(6)
      width, height, packed, background, = reader.bytes(7).unpack("vvCCC")
      raise ArgumentError, "GIF too large" unless width.positive? && height.positive? && width * height <= max_pixels
      global_palette = palette(reader, packed)
      canvas = Array.new(width * height, [0, 0, 0, 0].freeze)
      frames, gce = [], {delay: 0, disposal: 0, transparent: nil}

      until reader.eof?
        marker = reader.byte
        case marker
        when 0x3b then break
        when 0x21
          label = reader.byte
          if label == 0xf9
            reader.byte # block size
            flags, delay, transparent = reader.bytes(4).unpack("CvvC")
            reader.byte
            gce = {delay: delay * 0.01, disposal: (flags >> 2) & 7, transparent: flags.anybits?(1) ? transparent : nil}
          else
            skip_subblocks(reader)
          end
        when 0x2c
          frame = read_frame(reader, global_palette, width, height, canvas, gce)
          frames << frame[:frame]
          canvas = frame[:canvas]
          gce = {delay: 0, disposal: 0, transparent: nil}
        else
          raise ArgumentError, "invalid GIF block"
        end
      end
      raise ArgumentError, "GIF has no frames" if frames.empty?

      [width, height, frames.freeze]
    rescue IndexError => error
      raise ArgumentError, "truncated GIF: #{error.message}"
    end

    def palette(reader, packed)
      return [] unless packed.anybits?(0x80)
      size = 2**((packed & 7) + 1)
      reader.bytes(size * 3).bytes.each_slice(3).map { |rgb| [*rgb, 255].freeze }.freeze
    end
    private_class_method :palette

    def read_frame(reader, global_palette, width, height, previous, gce)
      left, top, frame_width, frame_height, packed = reader.bytes(9).unpack("vvvvC")
      local_palette = palette(reader, packed)
      palette = local_palette.empty? ? global_palette : local_palette
      raise ArgumentError, "GIF frame has no palette" if palette.empty?
      interlaced = packed.anybits?(0x40)
      min_code_size = reader.byte
      compressed = subblocks(reader)
      indices = lzw_decode(compressed, min_code_size, frame_width * frame_height)
      indices = deinterlace(indices, frame_width, frame_height) if interlaced
      canvas = previous.map(&:dup)
      saved = canvas.map(&:dup) if gce[:disposal] == 3
      frame_height.times do |row|
        frame_width.times do |column|
          index = indices[row * frame_width + column]
          next if index == gce[:transparent]
          color = palette[index] || [0, 0, 0, 0].freeze
          x, y = left + column, top + row
          canvas[y * width + x] = color if x.between?(0, width - 1) && y.between?(0, height - 1)
        end
      end
      pixels = canvas.flatten.pack("C*")
      frame = Frame.new(pixels, gce[:delay], gce[:disposal])
      disposed = case gce[:disposal]
      when 2
        canvas.map.with_index { |color, index| image_in_frame?(index, left, top, frame_width, frame_height, width) ? [0, 0, 0, 0].freeze : color }
      when 3 then saved || canvas
      else canvas
      end
      {frame: frame, canvas: disposed}
    end
    private_class_method :read_frame

    def image_in_frame?(index, left, top, frame_width, frame_height, width)
      x, y = index % width, index / width
      x >= left && x < left + frame_width && y >= top && y < top + frame_height
    end
    private_class_method :image_in_frame?

    def skip_subblocks(reader)
      loop do
        length = reader.byte
        break if length.zero?
        reader.skip(length)
      end
    end
    private_class_method :skip_subblocks

    def subblocks(reader)
      result = +"".b
      loop do
        length = reader.byte
        break if length.zero?
        result << reader.bytes(length)
      end
      result
    end
    private_class_method :subblocks

    def deinterlace(indices, width, height)
      output = Array.new(indices.length)
      offset = 0
      [0, 4, 2, 1].zip([8, 8, 4, 2]).each do |start, step|
        (start...height).step(step) do |row|
          output[row * width, width] = indices[offset, width]
          offset += width
        end
      end
      output
    end
    private_class_method :deinterlace

    def lzw_decode(bytes, minimum, expected)
      raise ArgumentError, "invalid GIF LZW size" unless minimum.between?(2, 8)
      clear, stop, code_size = 1 << minimum, (1 << minimum) + 1, minimum + 1
      table = (0...clear).map { |value| [value] } + [nil, nil]
      bit_offset, previous, output = 0, nil, []
      read_code = lambda do
        value = 0
        code_size.times do |bit|
          byte = bytes.getbyte((bit_offset + bit) / 8) || 0
          value |= ((byte >> ((bit_offset + bit) % 8)) & 1) << bit
        end
        bit_offset += code_size
        value
      end
      loop do
        code = read_code.call
        break if code == stop || output.length >= expected
        if code == clear
          table = (0...clear).map { |value| [value] } + [nil, nil]
          code_size = minimum + 1
          previous = nil
          next
        end
        entry = if code < table.length && table[code]
          table[code]
        elsif previous
          previous + [previous.first]
        else
          raise ArgumentError, "invalid GIF LZW code"
        end
        output.concat(entry)
        if previous
          table << previous + [entry.first]
          code_size += 1 if table.length == (1 << code_size) && code_size < 12
        end
        previous = entry
      end
      raise ArgumentError, "truncated GIF image data" if output.length < expected
      output.first(expected)
    end
    private_class_method :lzw_decode

    class Reader
      def initialize(bytes) = (@bytes, @offset = bytes, 0)
      def eof? = @offset >= @bytes.bytesize
      def byte = bytes(1).getbyte(0)
      def bytes(length)
        value = @bytes.byteslice(@offset, length)
        raise IndexError, "unexpected end of input" unless value && value.bytesize == length
        @offset += length
        value
      end
      def skip(length) = bytes(length)
    end
  end
end
