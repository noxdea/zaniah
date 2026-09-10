# frozen_string_literal: true

require "zlib"

module Zaniah
  # Runtime headless output uses only the Ruby standard distribution.
  module PNG
    SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
    module_function

    def encode(width, height, rgba)
      raise ArgumentError, "invalid image dimensions" unless width.positive? && height.positive? && rgba.bytesize == width * height * 4
      scanlines = String.new(encoding: Encoding::BINARY)
      height.times { |row| scanlines << "\0" << rgba.byteslice(row * width * 4, width * 4) }
      SIGNATURE + chunk("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNC5")) +
        chunk("IDAT", Zlib::Deflate.deflate(scanlines)) + chunk("IEND", "".b)
    end

    def write(path, width, height, rgba) = File.binwrite(path, encode(width, height, rgba))

    def decode(bytes, max_pixels: 16_777_216)
      raise ArgumentError, "not a PNG" unless bytes.start_with?(SIGNATURE)

      header, compressed = parse_chunks(bytes)
      width, height, type, channels = decode_header(header, max_pixels)
      stride = width * channels
      raw = inflate(compressed, (stride + 1) * height)
      [width, height, decode_scanlines(raw, width, height, type, channels)]
    end

    def parse_chunks(bytes)
      offset, compressed, header, ended = 8, String.new(encoding: Encoding::BINARY), nil, false
      while offset + 12 <= bytes.bytesize
        size = bytes.byteslice(offset, 4).unpack1("N")
        raise ArgumentError, "truncated PNG" if offset + 12 + size > bytes.bytesize
        kind = bytes.byteslice(offset + 4, 4)
        data = bytes.byteslice(offset + 8, size)
        crc = bytes.byteslice(offset + 8 + size, 4).unpack1("N")
        raise ArgumentError, "PNG checksum mismatch" unless Zlib.crc32(kind + data) == crc
        case kind
        when "IHDR" then header = data.unpack("NNC5")
        when "IDAT" then compressed << data
        when "IEND" then ended = true; break
        end
        offset += size + 12
      end
      raise ArgumentError, "missing PNG header or end" unless header && ended

      [header, compressed]
    end

    def decode_header(header, max_pixels)
      width, height, depth, type, compression, filter, interlace = header
      raise ArgumentError, "unsupported PNG encoding" unless depth == 8 && compression == 0 && filter == 0 && interlace == 0 && [0, 2, 4, 6].include?(type)
      raise ArgumentError, "PNG too large" unless width.positive? && height.positive? && width * height <= max_pixels
      channels = {0 => 1, 2 => 3, 4 => 2, 6 => 4}.fetch(type)

      [width, height, type, channels]
    end

    def inflate(compressed, expected)
      raw = String.new(encoding: Encoding::BINARY)
      inflater = Zlib::Inflate.new
      begin
        inflater.inflate(compressed) do |part|
          raise ArgumentError, "excess PNG data" if raw.bytesize + part.bytesize > expected
          raw << part
        end
      ensure
        inflater.close
      end
      raise ArgumentError, "incorrect PNG data length" unless raw.bytesize == expected

      raw
    end

    def decode_scanlines(raw, width, height, type, channels)
      stride = width * channels
      previous = Array.new(stride, 0)
      rgba = String.new(capacity: width * height * 4, encoding: Encoding::BINARY)
      height.times do |row|
        method = raw.getbyte(row * (stride + 1))
        raise ArgumentError, "invalid PNG filter" unless (0..4).cover?(method)
        current = raw.byteslice(row * (stride + 1) + 1, stride).bytes
        stride.times do |i|
          left = i < channels ? 0 : current[i - channels]
          up, upper_left = previous[i], i < channels ? 0 : previous[i - channels]
          prediction = case method
          when 0 then 0
          when 1 then left
          when 2 then up
          when 3 then (left + up) / 2
          when 4
            p = left + up - upper_left
            [left, up, upper_left].min_by { |v| (p - v).abs }
          end
          current[i] = (current[i] + prediction) & 255
        end
        current.each_slice(channels) do |pixel|
          rgba << case type
          when 0 then [pixel[0], pixel[0], pixel[0], 255].pack("C4")
          when 2 then [*pixel, 255].pack("C4")
          when 4 then [pixel[0], pixel[0], pixel[0], pixel[1]].pack("C4")
          when 6 then pixel.pack("C4")
          end
        end
        previous = current
      end
      rgba
    end

    def chunk(kind, data)
      [data.bytesize].pack("N") + kind + data + [Zlib.crc32(kind + data)].pack("N")
    end

    private_class_method :parse_chunks, :decode_header, :inflate, :decode_scanlines
  end
end
