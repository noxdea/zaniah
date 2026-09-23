# frozen_string_literal: true

module Zaniah
  module JPEG
    class Error < ArgumentError; end

    ZIGZAG = [
      0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
      12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
      35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
      58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63
    ].freeze
    COS = Array.new(8) do |x|
      Array.new(8) { |u| Math.cos((2 * x + 1) * u * Math::PI / 16) }.freeze
    end.freeze
    SCALE = [1 / Math.sqrt(2), 1, 1, 1, 1, 1, 1, 1].freeze

    module_function

    def decode(bytes, max_pixels: 16_777_216)
      raise Error, "not a JPEG" unless bytes.is_a?(String) && bytes.start_with?("\xFF\xD8".b)
      raise ArgumentError, "max_pixels must be a positive integer" unless max_pixels.is_a?(Integer) && max_pixels.positive?
      Decoder.new(bytes, max_pixels).decode
    end

    class Huffman
      def initialize(counts, values)
        @codes = {}
        code = index = 0
        counts.each_with_index do |count, length|
          raise Error, "oversubscribed JPEG Huffman table" if code + count > (1 << (length + 1))
          count.times do
            value = values[index]
            raise Error, "invalid JPEG Huffman table" unless value
            @codes[[length + 1, code]] = value
            code += 1
            index += 1
          end
          code <<= 1
        end
        raise Error, "invalid JPEG Huffman table" unless index == values.length
      end

      def decode(reader)
        code = 0
        1.upto(16) do |length|
          code = (code << 1) | reader.bit
          return @codes[[length, code]] if @codes.key?([length, code])
        end
        raise Error, "invalid JPEG Huffman code"
      end
    end

    class BitReader
      def initialize(bytes, offset)
        @bytes, @offset, @value, @remaining = bytes, offset, 0, 0
      end

      def bit
        if @remaining.zero?
          @value = data_byte
          @remaining = 8
        end
        @remaining -= 1
        (@value >> @remaining) & 1
      end

      def bits(count)
        value = 0
        count.times { value = (value << 1) | bit }
        value
      end

      def restart!(expected)
        @remaining = 0
        marker = read_marker
        raise Error, "expected JPEG restart marker" unless marker == expected
      end

      def finish!
        @remaining = 0
        raise Error, "JPEG image is missing its end marker" unless read_marker == 0xd9
      end

      private

      def data_byte
        byte = @bytes.getbyte(@offset)
        raise Error, "truncated JPEG scan" unless byte
        @offset += 1
        return byte unless byte == 0xff
        marker = read_marker
        return 0xff if marker == 0
        raise Error, "unexpected marker in JPEG scan"
      end

      def read_marker
        raise Error, "truncated JPEG marker" unless @bytes.getbyte(@offset) == 0xff
        @offset += 1 while @bytes.getbyte(@offset) == 0xff
        marker = @bytes.getbyte(@offset)
        raise Error, "truncated JPEG marker" unless marker
        @offset += 1
        marker
      end
    end

    class Decoder
      def initialize(bytes, max_pixels)
        @bytes, @max_pixels, @offset = bytes.b, max_pixels, 2
        @quantization, @huffman, @components = {}, {}, []
        @orientation, @restart_interval = 1, 0
        @adobe_transform = nil
      end

      def decode
        scan_offset = read_headers
        initialize_planes
        reader = BitReader.new(@bytes, scan_offset)
        decode_scan(reader)
        reader.finish!
        rgba = render_pixels
        orient(*rgba)
      end

      private

      def read_headers
        loop do
          marker = next_marker
          break if marker == 0xd9
          length = read_u16
          raise Error, "invalid JPEG segment length" if length < 2 || @offset + length - 2 > @bytes.bytesize
          data = @bytes.byteslice(@offset, length - 2)
          @offset += length - 2
          case marker
          when 0xdb then read_quantization(data)
          when 0xc4 then read_huffman(data)
          when 0xc0 then read_frame(data)
          when 0xc2 then raise Error, "progressive JPEG is not supported"
          when 0xc1 then raise Error, "extended sequential JPEG is not supported"
          when 0xdd
            raise Error, "invalid JPEG restart interval" unless data.bytesize == 2
            @restart_interval = data.unpack1("n")
          when 0xe1 then @orientation = exif_orientation(data)
          when 0xee then @adobe_transform = data.getbyte(11) if data.start_with?("Adobe".b)
          when 0xda then return read_scan_header(data)
          when 0xc3, 0xc5..0xcf
            raise Error, "unsupported JPEG coding process"
          end
        end
        raise Error, "JPEG scan is missing"
      end

      def next_marker
        @offset += 1 while @offset < @bytes.bytesize && @bytes.getbyte(@offset) != 0xff
        raise Error, "truncated JPEG marker" if @offset + 1 >= @bytes.bytesize
        @offset += 1 while @bytes.getbyte(@offset) == 0xff
        marker = @bytes.getbyte(@offset)
        raise Error, "invalid JPEG marker" unless marker && marker != 0
        @offset += 1
        marker
      end

      def read_u16
        raise Error, "truncated JPEG segment" if @offset + 2 > @bytes.bytesize
        value = @bytes.unpack1("@#{@offset}n")
        @offset += 2
        value
      end

      def read_quantization(data)
        offset = 0
        while offset < data.bytesize
          info = data.getbyte(offset)
          offset += 1
          precision, id = info >> 4, info & 15
          raise Error, "invalid JPEG quantization table" unless precision <= 1 && id < 4
          bytes = precision.zero? ? 1 : 2
          raise Error, "truncated JPEG quantization table" if offset + 64 * bytes > data.bytesize
          values = 64.times.map do
            value = bytes == 1 ? data.getbyte(offset) : data.unpack1("@#{offset}n")
            offset += bytes
            value
          end
          table = Array.new(64)
          ZIGZAG.each_with_index { |index, zigzag| table[index] = values[zigzag] }
          raise Error, "zero JPEG quantization value" if table.any?(&:zero?)
          @quantization[id] = table.freeze
        end
      end

      def read_huffman(data)
        offset = 0
        while offset < data.bytesize
          info = data.getbyte(offset)
          offset += 1
          kind, id = info >> 4, info & 15
          raise Error, "invalid JPEG Huffman table" unless kind <= 1 && id < 4 && offset + 16 <= data.bytesize
          counts = data.byteslice(offset, 16).bytes
          offset += 16
          length = counts.sum
          raise Error, "truncated JPEG Huffman values" if offset + length > data.bytesize
          @huffman[[kind, id]] = Huffman.new(counts, data.byteslice(offset, length).bytes)
          offset += length
        end
      end

      def read_frame(data)
        raise Error, "duplicate JPEG frame" unless @components.empty?
        raise Error, "invalid JPEG frame" if data.bytesize < 6
        precision, @height, @width, count = data.unpack("CnnC")
        raise Error, "only 8-bit JPEG is supported" unless precision == 8
        raise Error, "invalid JPEG dimensions" unless @width.positive? && @height.positive? && @width * @height <= @max_pixels
        raise Error, "only grayscale and YCbCr/RGB JPEG are supported" unless [1, 3].include?(count) && data.bytesize == 6 + count * 3
        offset = 6
        count.times do
          id, sampling, quant = data.byteslice(offset, 3).bytes
          h, v = sampling >> 4, sampling & 15
          raise Error, "invalid JPEG sampling factors" unless h.between?(1, 4) && v.between?(1, 4) && quant < 4
          raise Error, "duplicate JPEG component" if @components.any? { |component| component[:id] == id }
          @components << {id: id, h: h, v: v, quant: quant, dc: 0, dc_id: nil, ac_id: nil}
          offset += 3
        end
        @max_h = @components.map { |component| component[:h] }.max
        @max_v = @components.map { |component| component[:v] }.max
        raise Error, "too many JPEG blocks per MCU" if @components.sum { |component| component[:h] * component[:v] } > 10
        mcu_w, mcu_h = @max_h * 8, @max_v * 8
        @mcu_columns, @mcu_rows = (@width + mcu_w - 1) / mcu_w, (@height + mcu_h - 1) / mcu_h
      end

      def read_scan_header(data)
        raise Error, "JPEG frame is missing" if @components.empty?
        raise Error, "invalid JPEG scan" if data.empty?
        count, offset = data.getbyte(0), 1
        raise Error, "only a single baseline scan is supported" unless count == @components.length && data.bytesize == 1 + count * 2 + 3
        @scan_components = []
        count.times do
          id, selectors = data.byteslice(offset, 2).bytes
          component = @components.find { |item| item[:id] == id }
          raise Error, "unknown or duplicate JPEG scan component" unless component && !@scan_components.include?(component)
          component[:dc_id], component[:ac_id] = selectors >> 4, selectors & 15
          @scan_components << component
          offset += 2
        end
        start, finish, successive = data.byteslice(offset, 3).bytes
        raise Error, "unsupported non-baseline JPEG scan" unless start.zero? && finish == 63 && successive.zero?
        @components.each do |component|
          raise Error, "missing JPEG quantization table" unless @quantization[component[:quant]]
          raise Error, "missing JPEG Huffman table" unless @huffman[[0, component[:dc_id]]] && @huffman[[1, component[:ac_id]]]
        end
        @offset
      end

      def initialize_planes
        @components.each do |component|
          component[:plane_width] = @mcu_columns * component[:h] * 8
          component[:plane_height] = @mcu_rows * component[:v] * 8
          component[:width] = (@width * component[:h] + @max_h - 1) / @max_h
          component[:height] = (@height * component[:v] + @max_v - 1) / @max_v
          component[:plane] = String.new(capacity: component[:plane_width] * component[:plane_height], encoding: Encoding::BINARY)
          component[:plane] << "\x80".b * (component[:plane_width] * component[:plane_height])
        end
      end

      def decode_scan(reader)
        total = @mcu_columns * @mcu_rows
        total.times do |mcu|
          @scan_components.each do |component|
            component[:v].times do |block_y|
              component[:h].times do |block_x|
                values = decode_block(component, reader)
                x = ((mcu % @mcu_columns) * component[:h] + block_x) * 8
                y = ((mcu / @mcu_columns) * component[:v] + block_y) * 8
                write_block(component, values, x, y)
              end
            end
          end
          if @restart_interval.positive? && (mcu + 1) < total && (mcu + 1) % @restart_interval == 0
            reader.restart!(0xd0 + ((mcu + 1) / @restart_interval - 1) % 8)
            @components.each { |component| component[:dc] = 0 }
          end
        end
      end

      def decode_block(component, reader)
        coefficients = Array.new(64, 0)
        dc_size = @huffman.fetch([0, component[:dc_id]]).decode(reader)
        raise Error, "invalid JPEG DC coefficient" if dc_size > 11
        component[:dc] += receive(reader, dc_size)
        coefficients[0] = component[:dc]
        index = 1
        table = @huffman.fetch([1, component[:ac_id]])
        while index < 64
          value = table.decode(reader)
          run, size = value >> 4, value & 15
          if size.zero?
            break if run.zero?
            raise Error, "invalid JPEG zero run" unless run == 15
            index += 16
            raise Error, "invalid JPEG coefficient run" if index > 64
          else
            raise Error, "invalid JPEG AC coefficient" if size > 10
            index += run
            raise Error, "invalid JPEG coefficient run" if index >= 64
            coefficients[ZIGZAG[index]] = receive(reader, size)
            index += 1
          end
        end
        quant = @quantization.fetch(component[:quant])
        idct(coefficients.each_index.map { |i| coefficients[i] * quant[i] })
      end

      def receive(reader, size)
        return 0 if size.zero?
        value = reader.bits(size)
        value < (1 << (size - 1)) ? value - ((1 << size) - 1) : value
      end

      def idct(coefficients)
        temp = Array.new(8) { Array.new(8, 0.0) }
        8.times do |v|
          8.times do |x|
            sum = 0.0
            8.times { |u| sum += SCALE[u] * coefficients[v * 8 + u] * COS[x][u] }
            temp[v][x] = sum
          end
        end
        Array.new(64) do |index|
          y, x = index.divmod(8)
          sum = 0.0
          8.times { |v| sum += SCALE[v] * temp[v][x] * COS[y][v] }
          [[(sum * 0.25 + 128).round, 0].max, 255].min
        end
      end

      def write_block(component, pixels, x, y)
        8.times do |row|
          bytes = pixels.slice(row * 8, 8).pack("C8")
          component[:plane][(y + row) * component[:plane_width] + x, 8] = bytes
        end
      end

      def render_pixels
        rgba = String.new(capacity: @width * @height * 4, encoding: Encoding::BINARY)
        y_component, cb_component, cr_component = @components
        @height.times do |y|
          @width.times do |x|
            if @components.length == 1
              gray = sample(y_component, x, y)
              rgba << [gray, gray, gray, 255].pack("C4")
            elsif @adobe_transform == 0
              rgba << [sample(y_component, x, y), sample(cb_component, x, y), sample(cr_component, x, y), 255].pack("C4")
            else
              yy = sample(y_component, x, y)
              cb = sample(cb_component, x, y) - 128
              cr = sample(cr_component, x, y) - 128
              r = (yy + 1.402 * cr).round.clamp(0, 255)
              g = (yy - 0.344136 * cb - 0.714136 * cr).round.clamp(0, 255)
              b = (yy + 1.772 * cb).round.clamp(0, 255)
              rgba << [r, g, b, 255].pack("C4")
            end
          end
        end
        [@width, @height, rgba]
      end

      def sample(component, x, y)
        x_ratio, y_ratio = component[:h].to_f / @max_h, component[:v].to_f / @max_v
        fx = ((x + 0.5) * x_ratio - 0.5).clamp(0, (component[:width] - 1).to_f)
        fy = ((y + 0.5) * y_ratio - 0.5).clamp(0, (component[:height] - 1).to_f)
        x0, y0 = fx.floor, fy.floor
        x1, y1 = [x0 + 1, component[:width] - 1].min, [y0 + 1, component[:height] - 1].min
        a = component[:plane].getbyte(y0 * component[:plane_width] + x0)
        b = component[:plane].getbyte(y0 * component[:plane_width] + x1)
        c = component[:plane].getbyte(y1 * component[:plane_width] + x0)
        d = component[:plane].getbyte(y1 * component[:plane_width] + x1)
        top = a + (b - a) * (fx - x0)
        bottom = c + (d - c) * (fx - x0)
        (top + (bottom - top) * (fy - y0)).round
      end

      def orient(width, height, pixels)
        return [width, height, pixels] if @orientation == 1
        out_width, out_height = @orientation.between?(5, 8) ? [height, width] : [width, height]
        output = String.new(capacity: out_width * out_height * 4, encoding: Encoding::BINARY)
        out_height.times do |y|
          out_width.times do |x|
            sx, sy = case @orientation
            when 2 then [width - 1 - x, y]
            when 3 then [width - 1 - x, height - 1 - y]
            when 4 then [x, height - 1 - y]
            when 5 then [y, x]
            when 6 then [y, height - 1 - x]
            when 7 then [width - 1 - y, height - 1 - x]
            when 8 then [width - 1 - y, x]
            else [x, y]
            end
            output << pixels.byteslice((sy * width + sx) * 4, 4)
          end
        end
        [out_width, out_height, output]
      end

      def exif_orientation(data)
        return 1 unless data.start_with?("Exif\0\0".b) && data.bytesize >= 14
        tiff = data.byteslice(6..)
        endian = case tiff.byteslice(0, 2)
        when "II" then :little
        when "MM" then :big
        else return 1
        end
        u16 = ->(offset) { tiff.byteslice(offset, 2)&.unpack1(endian == :little ? "v" : "n") }
        u32 = ->(offset) { tiff.byteslice(offset, 4)&.unpack1(endian == :little ? "V" : "N") }
        return 1 unless u16.call(2) == 42
        ifd = u32.call(4)
        return 1 unless ifd && ifd + 2 <= tiff.bytesize
        count = u16.call(ifd)
        return 1 unless count && ifd + 2 + count * 12 <= tiff.bytesize
        count.times do |index|
          entry = ifd + 2 + index * 12
          next unless u16.call(entry) == 0x0112 && u16.call(entry + 2) == 3 && u32.call(entry + 4) == 1
          value = u16.call(entry + 8)
          return value if value&.between?(1, 8)
        end
        1
      rescue StandardError
        1
      end
    end
  end
end
