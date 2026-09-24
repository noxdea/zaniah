# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/platform/mac/clipboard_data"

class MacClipboardDataTest < Minitest::Test
  Data = Zaniah::Platform::Mac::ClipboardData

  def test_mime_type_mapping_and_file_urls
    assert_equal "public.utf8-plain-text", Data.native_type("text/plain")
    assert_equal "public.html", Data.native_type("text/html")
    assert_equal "public.png", Data.native_type("image/png")
    assert_match(/\Acom\.noxdea\.zaniah\.mime\.[0-9a-f]+\z/, Data.native_type("application/x-test"))
    assert_equal "application/x-test", Data.mime_type(Data.native_type("application/x-test"))
    assert_equal "text/uri-list", Data.mime_type("public.file-url")
    assert_nil Data.mime_type("com.apple.private-type")
    assert_equal ["file:///tmp/one", "file:///tmp/two"], Data.file_urls("# comment\r\nfile:///tmp/one\r\nhttps://example.com\r\nfile:///tmp/two\r\n")
  end
end
