# frozen_string_literal: true

require "uri"
require_relative "../../png"

module Zaniah
  module Platform
    module Windows
      # Byte-level formats shared by the native clipboard adapter and host-independent tests.
      module ClipboardData
        module_function

        def format_html(fragment)
          fragment = fragment.encode(Encoding::UTF_8).b
          prefix = "<html><body><!--StartFragment-->".b
          suffix = "<!--EndFragment--></body></html>".b
          header = "Version:1.0\r\nStartHTML:%010d\r\nEndHTML:%010d\r\nStartFragment:%010d\r\nEndFragment:%010d\r\n"
          start_html = format(header, 0, 0, 0, 0).bytesize
          start_fragment = start_html + prefix.bytesize
          end_fragment = start_fragment + fragment.bytesize
          end_html = end_fragment + suffix.bytesize
          format(header, start_html, end_html, start_fragment, end_fragment).b + prefix + fragment + suffix
        end

        def parse_html(bytes)
          offsets = %w[StartFragment EndFragment].to_h do |name|
            value = bytes[/^#{name}:\s*(\d+)\s*\r?$/i, 1]
            raise ArgumentError, "invalid CF_HTML #{name}" unless value
            [name, value.to_i]
          end
          first, last = offsets.values
          raise ArgumentError, "invalid CF_HTML fragment range" unless first <= last && last <= bytes.bytesize
          html_start = bytes[/^StartHTML:\s*(-?\d+)\s*\r?$/i, 1]&.to_i
          html_end = bytes[/^EndHTML:\s*(-?\d+)\s*\r?$/i, 1]&.to_i
          if html_start && html_end && html_start >= 0
            raise ArgumentError, "invalid CF_HTML context range" unless html_start <= first && last <= html_end && html_end <= bytes.bytesize
          end
          fragment = bytes.byteslice(first...last).force_encoding(Encoding::UTF_8)
          raise ArgumentError, "invalid CF_HTML UTF-8" unless fragment.valid_encoding?
          fragment
        end

        def file_paths(uri_list)
          uri_list.each_line.filter_map do |line|
            next if line.start_with?("#") || line.strip.empty?
            uri = URI.parse(line.strip)
            return nil unless uri.scheme == "file" && uri.query.nil? && uri.fragment.nil?
            path = URI::RFC2396_PARSER.unescape(uri.path.to_s).force_encoding(Encoding::UTF_8)
            return nil unless path.valid_encoding? && !path.include?("\0")
            if uri.host && !uri.host.empty? && uri.host != "localhost"
              "\\\\#{uri.host}#{path.tr('/', '\\')}"
            elsif path.match?(%r{\A/[A-Za-z]:/})
              path.delete_prefix("/").tr("/", "\\")
            else
              return nil
            end
          rescue URI::InvalidURIError
            return nil
          end
        end

        def uri_list(paths)
          paths.map do |path|
            normalized = path.tr("\\", "/")
            if normalized.start_with?("//")
              host, rest = normalized.delete_prefix("//").split("/", 2)
              "file://#{host}/#{URI::RFC2396_PARSER.escape(rest.to_s, /[^A-Za-z0-9\-._~\/:]/)}"
            else
              "file:///#{URI::RFC2396_PARSER.escape(normalized, /[^A-Za-z0-9\-._~\/:]/)}"
            end
          end.join("\r\n") + "\r\n"
        end

        def hdrop(paths)
          payload = paths.map { |path| path.encode(Encoding::UTF_16LE).b + "\0\0".b }.join + "\0\0".b
          [20, 0, 0, 0, 1].pack("L<l<l<L<L<") + payload
        end

        def dibv5_to_png(bytes)
          raise ArgumentError, "invalid CF_DIBV5 header" if bytes.bytesize < 124 || bytes.unpack1("L<") < 124
          width, height, planes, depth, compression = bytes.byteslice(4, 16).unpack("l<l<S<S<L<")
          raise ArgumentError, "unsupported CF_DIBV5 bitmap" unless width.positive? && !height.zero? && planes == 1 && [24, 32].include?(depth) && [0, 3].include?(compression)
          rows = height.abs
          raise ArgumentError, "CF_DIBV5 bitmap too large" if width * rows > 16_777_216
          stride = ((width * depth + 31) / 32) * 4
          offset = bytes.unpack1("L<")
          raise ArgumentError, "truncated CF_DIBV5 bitmap" if bytes.bytesize < offset + stride * rows
          red, green, blue, alpha = bytes.byteslice(40, 16).unpack("L<4")
          masks = compression == 3 ? [red, green, blue, alpha] : [0x00ff0000, 0x0000ff00, 0x000000ff, 0]
          raise ArgumentError, "unsupported CF_DIBV5 color masks" if masks.take(3).any?(&:zero?)
          rgba = String.new(capacity: width * rows * 4, encoding: Encoding::BINARY)
          rows.times do |row|
            source_row = height.positive? ? rows - 1 - row : row
            scanline = bytes.byteslice(offset + source_row * stride, stride)
            width.times do |column|
              pixel = scanline.byteslice(column * (depth / 8), depth / 8).ljust(4, "\0").unpack1("L<")
              rgba << masks.map.with_index { |mask, index| component(pixel, mask, index == 3 ? 255 : 0) }.pack("C4")
            end
          end
          PNG.encode(width, rows, rgba)
        end

        def component(pixel, mask, fallback)
          return fallback if mask.zero?
          shift = (mask & -mask).bit_length - 1
          maximum = mask >> shift
          (((pixel & mask) >> shift) * 255 + maximum / 2) / maximum
        end
        private_class_method :component
      end
    end
  end
end
