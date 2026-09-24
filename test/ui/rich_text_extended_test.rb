# frozen_string_literal: true

require_relative "../test_helper"
require "zaniah/ui"

class RichTextExtendedTest < Minitest::Test
  class CountingTextSystem
    attr_reader :calls
    def initialize = @calls = []
    def layout_line(text, font: nil, size: 14, direction: :auto)
      @calls << text
      byte, carets = 0, [[0, 0.0]]
      text.each_grapheme_cluster do |cluster|
        byte += cluster.bytesize
        carets << [byte, carets.length * 10.0]
      end
      Zaniah::TextSystem::LineLayout.new(text, [], carets.last.last, 12, 4, size, carets)
    end
    def paint_line(*) = nil
    def close = nil
  end

  def setup
    @app = Zaniah::App.new
    @window = @app.open_window(width: 320, height: 160)
    @window.text_system = CountingTextSystem.new
  end

  def teardown
    @window.close
    @app.executor.shutdown
  end

  def render(component)
    @window.draw { component }
    @window.request_frame
    @window.tick
    component
  end

  def test_inline_and_paragraph_styles_paint_and_validate
    rich = Zaniah::UI::RichText.new([{text: "hello", underline: :double,
      underline_color: "#f00", strikethrough: true, background: "#222",
      baseline: :superscript, letter_spacing: 2}]).w(200)
    rich.paragraph_style(0...5, indent: 8, quote: true, background: "#333",
      spacing_before: 4, spacing_after: 6)
    render(rich)
    assert_equal 2, rich.spans.first.style[:letter_spacing]
    assert_equal :double, rich.spans.first.style[:underline]
    assert_equal 8, rich.paragraph_styles.first[:indent]
    assert_operator rich.root.instance_variable_get(:@content_height), :>, 20
    assert_raises(ArgumentError) { rich.apply(0...1, underline: :triple) }
  end

  def test_embed_uses_object_replacement_and_inline_width
    rich = Zaniah::UI::RichText.new("ab").w(200)
    rich.insert_embed(1, key: :chip, width: 30, height: 18) do |_cx|
      Zaniah::Div.new.w(30).h(18).bg("#f00")
    end
    rich.apply(1...4, background: "#00f")
    render(rich)
    assert_equal "a\uFFFCb", rich.text
    assert_equal 1, rich.embeds.length
    assert_equal 1, rich.root.children.length
    line = rich.root.instance_variable_get(:@lines).first
    marker = line.runs.find { |run| run.start == 1 }
    assert_equal 30, marker.layout.width
    bounds = rich.root.children.first.layout_node.bounds
    pixel = @window.device.pixels.byteslice(((bounds.y + 9).to_i * @window.device.width +
      (bounds.x + 15).to_i) * 4, 4).bytes
    assert_equal [255, 0, 0, 255], pixel
    rich.delete(1...4)
    assert_empty rich.embeds
    rich.text_action(:undo)
    assert_equal "a\uFFFCb", rich.text
    assert_equal :chip, rich.embeds.first.key
  end

  def test_append_reuses_earlier_paragraph_layout
    rich = Zaniah::UI::RichText.new("first\nlast").w(220)
    render(rich)
    system = @window.text_system
    assert_includes system.calls, "first"
    first_line = rich.root.instance_variable_get(:@lines).first
    system.calls.clear
    rich.append(" more", style: {color: "#f00"})
    render(rich)
    refute_includes system.calls, "first"
    assert_same first_line, rich.root.instance_variable_get(:@lines).first
    assert_equal "first\nlast more", rich.text
    assert_equal "#f00", rich.spans.last.style[:color]
  end

  def test_wrapped_ascii_tail_keeps_rtl_paragraph_alignment
    rich = Zaniah::UI::RichText.new("שלום 123 abc").w(65)
    render(rich)
    lines = rich.root.instance_variable_get(:@lines)
    tail = lines.find { |line| rich.text.byteslice(line.start...line.finish).ascii_only? }
    refute_nil tail
    assert_operator tail.x, :>, 0
  end

  def test_ruby_is_one_selection_cluster_and_read_aloud_with_parent
    rich = Zaniah::UI::RichText.new([{text: "漢字", ruby: "かんじ"}]).w(200)
    render(rich)
    run = rich.root.instance_variable_get(:@lines).first.runs.first
    assert_equal 30, run.layout.width
    assert_operator run.layout.ascent, :>, 12
    assert_equal "漢字（かんじ）", rich.ruby_reading
    assert_equal "漢字（かんじ）", rich.tui_cells
    assert_raises(ArgumentError) { rich.selection = Zaniah::TextSelection.new(3) }
    assert_raises(ArgumentError) { rich.apply(0...3, color: "#f00") }
    rich.text_action(:move_right)
    assert_equal rich.text.bytesize, rich.selection.head
    rich.text_action(:move_left)
    assert_equal 0, rich.selection.head
    rich.selection = Zaniah::TextSelection.new(0, rich.text.bytesize)
    rich.text_action(:copy)
    assert_equal "漢字", @window.clipboard
  end

  def test_vertical_ruby_and_upright_combination_use_inline_boxes
    rich = Zaniah::UI::RichText.new([
      {text: "漢", ruby: "かん"}, {text: "12", combine_upright: true},
      {text: "字"}
    ], writing_mode: :vertical_rl).h(40)
    render(rich)
    lines = rich.root.instance_variable_get(:@lines)
    assert lines.all? { |line| line.runs.all? { |run| run.layout.writing_mode == :vertical_rl } }
    assert_equal lines.map(&:x).sort.reverse, lines.map(&:x)
    ruby = lines.flat_map(&:runs).find { |run| run.style[:ruby] }
    combined = lines.flat_map(&:runs).find { |run| run.style[:combine_upright] }
    refute_nil ruby
    refute_nil combined
    assert_equal 14, combined.layout.width
    assert_operator ruby.layout.ascent, :>, combined.layout.ascent
    assert_equal "漢（かん）12字", rich.accessibility_node(Zaniah::FrameContext.new(@window)).value
  end

  def test_ruby_parent_never_wraps_mid_cluster
    rich = Zaniah::UI::RichText.new([
      {text: "a"}, {text: "漢字", ruby: "かんじ"}, {text: "b"}
    ]).w(15)
    render(rich)
    boundaries = rich.root.instance_variable_get(:@lines).flat_map { |line| [line.start, line.finish] }
    refute boundaries.any? { |byte| byte > 1 && byte < 7 }
    assert_equal "漢字", rich.text.byteslice(1...7)
  end

  def test_navigation_never_stops_inside_ruby_and_styles_reject_conflicts
    rich = Zaniah::UI::RichText.new([{text: "first word", ruby: "reading"}, {text: " next"}])
    rich.text_action(:word_right)
    assert_equal 10, rich.selection.head
    rich.text_action(:line_end)
    assert_equal rich.text.bytesize, rich.selection.head
    rich.text_action(:word_left)
    assert_equal 11, rich.selection.head
    assert_raises(ArgumentError) do
      Zaniah::UI::RichText.new([{text: "x", ruby: "reading", combine_upright: true}])
    end
    assert_raises(ArgumentError) do
      Zaniah::UI::RichText.new([{text: "x", ruby: "reading".encode(Encoding::UTF_16LE)}])
    end
  end
end
