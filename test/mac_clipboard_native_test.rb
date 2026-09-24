# frozen_string_literal: true

require_relative "test_helper"

if RUBY_PLATFORM.include?("darwin")
  require "zaniah/platform/mac"

  class MacClipboardNativeTest < Minitest::Test
    O = Zaniah::FFI::ObjC

    def setup
      @pool = O.new("NSAutoreleasePool")
      @board = O.send(O.klass("NSPasteboard"), "pasteboardWithUniqueName")
      skip "NSPasteboard service unavailable" if @board.zero?
      @window = Zaniah::Platform::Mac::Window.allocate
      board = @board
      @window.define_singleton_method(:pasteboard) { board }
    end

    def teardown
      O.send(@board, "releaseGlobally", result: :void) if @board && !@board.zero?
      O.release(@pool) if @pool
    end

    def test_multiple_formats_items_and_text_shortcut
      @window.write_clipboard([
        Zaniah::Clipboard::Item.new("text/plain" => "日本語", "text/html" => "<b>日本語</b>", "image/png" => "\x89PNG".b),
        Zaniah::Clipboard::Item.new("application/x-zaniah-test" => "\0\xff".b)
      ])
      assert_equal ["text/plain", "text/html", "image/png", "application/x-zaniah-test"], @window.clipboard_types
      assert_equal "日本語", @window.clipboard
      content = @window.read_clipboard(types: ["application/x-zaniah-test", "text/html", "text/plain"])
      assert_equal ["application/x-zaniah-test", "text/html", "text/plain"], content.types
      assert_equal "\0\xff".b, content.fetch("application/x-zaniah-test")
      assert_equal "<b>日本語</b>", content.fetch("text/html")

      @window.clipboard = "plain"
      assert_equal ["text/plain"], @window.clipboard_types
      assert_equal "plain", @window.clipboard
    end

    def test_file_url_items_remain_visible_to_existing_file_drop_reader
      @window.write_clipboard([Zaniah::Clipboard::Item.new("text/uri-list" => "file:///tmp/one\r\nfile:///tmp/two\r\n")])
      assert_includes @window.clipboard_types, "text/uri-list"
      items = @window.pasteboard_items(@board)
      assert_equal 2, items.length
      assert_equal "file:///tmp/one", O.text(O.send(items.first, "stringForType:", O.string("public.file-url"), args: [:pointer]))
      assert_equal ["/tmp/one", "/tmp/two"], @window.clipboard_paths
      assert_equal "file:///tmp/one\r\nfile:///tmp/two\r\n", @window.read_clipboard(types: ["text/uri-list"]).fetch("text/uri-list")
    end
  end
end
