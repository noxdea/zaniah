# frozen_string_literal: true

require "uri"

module Zaniah
  module Platform
    module Mac
      module ClipboardData
        TYPES = {"text/plain" => "public.utf8-plain-text", "text/html" => "public.html", "image/png" => "public.png"}.freeze
        REVERSE_TYPES = TYPES.invert.freeze
        MIME_PREFIX = "com.noxdea.zaniah.mime."
        module_function

        def native_type(mime) = TYPES.fetch(mime) { MIME_PREFIX + mime.unpack1("H*") }
        def mime_type(native)
          return "text/uri-list" if native == "public.file-url"
          return REVERSE_TYPES[native] if REVERSE_TYPES.key?(native)
          return nil unless native.start_with?(MIME_PREFIX)
          hex = native.delete_prefix(MIME_PREFIX)
          return nil unless hex.match?(/\A(?:[0-9a-f]{2})+\z/)
          mime = [hex].pack("H*").force_encoding(Encoding::UTF_8)
          mime if mime.valid_encoding? && mime.match?(%r{\A[^\s/]+/[^\s/]+\z})
        end

        def file_urls(uri_list)
          uri_list.each_line.filter_map do |line|
            next if line.start_with?("#") || line.strip.empty?
            uri = URI.parse(line.strip)
            uri.to_s if uri.scheme == "file" && uri.query.nil? && uri.fragment.nil?
          rescue URI::InvalidURIError
            nil
          end
        end
      end
    end
  end
end
