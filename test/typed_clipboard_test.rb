# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/clipboard"
require "stringio"

class TypedClipboardTest < Minitest::Test
  def test_item_keeps_immutable_text_and_binary_representations
    text = +"hello"
    png = "\x89PNG".b
    formats = {"text/plain" => text, "image/png" => png}
    item = Zaniah::Clipboard::Item.new(formats)
    text.replace("changed")
    png.replace("changed")
    formats.clear

    assert_equal ["text/plain", "image/png"], item.types
    assert_equal "hello", item.fetch("text/plain")
    assert_equal "\x89PNG".b, item.fetch("image/png")
    assert_equal Encoding::UTF_8, item.fetch("text/plain").encoding
    assert_equal Encoding::BINARY, item.fetch("image/png").encoding
    assert item.frozen?
    assert_equal item, Zaniah::Clipboard::Item.new("text/plain" => "hello", "image/png" => "\x89PNG".b)
    assert_equal item.hash, Zaniah::Clipboard::Item.new("text/plain" => "hello", "image/png" => "\x89PNG".b).hash
    refute_equal item, Zaniah::Clipboard::Content.new("text/plain" => "hello", "image/png" => "\x89PNG".b)
    assert_raises(FrozenError) { item.fetch("text/plain").replace("bad") }
    assert_raises(KeyError) { item.fetch("text/html") }
  end

  def test_item_rejects_invalid_representations
    assert_raises(ArgumentError) { Zaniah::Clipboard::Item.new("invalid" => "data") }
    assert_raises(TypeError) { Zaniah::Clipboard::Item.new("image/png" => 1) }
    assert_raises(Encoding::InvalidByteSequenceError) { Zaniah::Clipboard::Item.new("text/plain" => "\xff".b) }
  end

  def test_headless_uses_request_order_and_preserves_per_window_items
    first = Zaniah::Platform::Headless::Window.new
    second = Zaniah::Platform::Headless::Window.new
    first.write_clipboard([
      Zaniah::Clipboard::Item.new("text/plain" => "a\tb", "text/html" => "<b>a</b>"),
      Zaniah::Clipboard::Item.new("image/png" => "\x89PNG".b)
    ])

    assert_equal ["text/plain", "text/html", "image/png"], first.clipboard_types
    content = first.read_clipboard(types: ["image/png", "text/plain", "missing/type"])
    assert_instance_of Zaniah::Clipboard::Content, content
    assert_equal ["image/png", "text/plain"], content.types
    assert_equal "a\tb", content.fetch("text/plain")
    assert_equal "", second.clipboard
    assert_empty second.clipboard_types

    first.clipboard = "plain"
    assert_equal ["text/plain"], first.clipboard_types
    assert_equal "plain", first.clipboard
  ensure
    first&.close
    second&.close
  end

  def test_tui_emits_osc52_only_for_text_and_once_per_write
    output = StringIO.new
    window = Zaniah::Platform::TUI::Window.new(input: StringIO.new, output: output)
    window.write_clipboard([Zaniah::Clipboard::Item.new("image/png" => "PNG".b)])
    assert_equal "", output.string
    window.write_clipboard([Zaniah::Clipboard::Item.new("text/plain" => "日", "text/html" => "<p>日</p>")])
    assert_equal "\e]52;c;5pel\a", output.string
    assert_equal ["text/plain", "text/html"], window.clipboard_types
    assert_equal "日", window.clipboard
    assert_equal "<p>日</p>", window.read_clipboard(types: ["text/html"]).fetch("text/html")
  ensure
    window&.close
  end
end
