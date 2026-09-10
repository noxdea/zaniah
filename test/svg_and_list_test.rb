# frozen_string_literal: true

require "test_helper"
require "zaniah/svg"
require "zaniah/list"

class SVGAndListTest < Minitest::Test
  def svg(body, attributes = "")
    Zaniah::SVG.new("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' #{attributes}>#{body}</svg>")
  end

  def pixel(texture, x, y) = texture.data.byteslice((y * texture.width + x) * 4, 4).bytes

  def test_svg_relative_paths_viewbox_colors_and_texture_cache
    icon = svg("<path d='m2 2h16v16h-16z' fill='currentColor'/>")
    raster = icon.texture(color: "#123456")
    assert_equal [0, 0, 0, 0], pixel(raster, 0, 0)
    assert_equal [18, 52, 86, 255], pixel(raster, 10, 10)
    assert_same raster, icon.texture(color: "#123456")
    wide = icon.texture(width: 40, height: 20, color: "#f00")
    assert_equal 0, pixel(wide, 2, 10)[3]
    assert_equal 255, pixel(wide, 20, 10)[3]
    stretch = svg("<rect width='20' height='20' fill='rgb(0, 100%, 0)'/>", "preserveAspectRatio='none'")
    assert_equal [0, 255, 0, 255], pixel(stretch.texture(width: 40, height: 20), 39, 19)
  end

  def test_nonzero_evenodd_holes_and_group_opacity
    path = "M1 1H19V19H1Z M5 5H15V15H5Z"
    assert_equal 255, pixel(svg("<path d='#{path}'/>").texture, 10, 10)[3]
    assert_equal 0, pixel(svg("<path d='#{path}' fill-rule='evenodd'/>").texture, 10, 10)[3]
    assert_equal 255, pixel(svg("<path d='#{path}' fill-rule='evenodd'/>").texture, 2, 2)[3]
    group = svg("<g opacity='.5' fill='red'><rect width='15' height='20'/><rect x='5' width='15' height='20'/></g>").texture
    assert_equal [255, 0, 0, 128], pixel(group, 2, 10)
    assert_equal [255, 0, 0, 128], pixel(group, 10, 10)
  end

  def test_arcs_smooth_curves_stroke_caps_and_transforms
    circle = svg("<path d='M18 10A8 8 0 0110 18A8 8 0 1118 10Z' fill='blue'/>").texture
    assert_equal [0, 0, 255, 255], pixel(circle, 10, 10)
    assert_equal 0, pixel(circle, 0, 0)[3]
    outline = Zaniah::SVG::Path.parse("M1e0 2 Q3 4 5 6t4 4 C10 11 12 13 14 15s2 2 3 3")
    assert_equal %i[move_to quad_to quad_to cubic_to cubic_to], outline.commands
    assert_equal [7.0, 8.0, 9.0, 10.0], outline.each.to_a[2].drop(1)
    line = svg("<g transform='translate(0 2)'><path d='M5 8H15' fill='none' stroke='red' stroke-width='4' stroke-linecap='round'/></g>").texture
    assert_equal [255, 0, 0, 255], pixel(line, 10, 10)
    assert_operator pixel(line, 3, 10)[3], :>, 100
    assert_equal 0, pixel(line, 2, 10)[3]
    rounded = svg("<rect x='2' y='2' width='16' height='16' rx='5'/>").texture
    assert_equal 0, pixel(rounded, 2, 2)[3]
    assert_equal 255, pixel(rounded, 10, 10)[3]
  end

  def test_definitions_use_and_clipping
    icon = svg("<defs><path id='shape' d='M0 0H10V20H0Z'/><clipPath id='clip'><circle cx='10' cy='10' r='5'/></clipPath></defs><g clip-path='url(#clip)'><use href='#shape' x='5' fill='blue'/></g>")
    assert_equal [0, 0, 255, 255], pixel(icon.texture, 10, 10)
    assert_equal 0, pixel(icon.texture, 6, 2)[3]
    assert_raises(ArgumentError) { svg("<use href='https://example.com/icon.svg'/>").texture }
    assert_raises(ArgumentError) { svg("<g id='loop'><use href='#loop'/></g>").texture }
    hole = svg("<defs><clipPath id='hole'><path fill='none' opacity='0' clip-rule='evenodd' d='M0 0H20V20H0Z M5 5H15V15H5Z'/></clipPath></defs><rect width='20' height='20' clip-path='url(#hole)'/>").texture
    assert_equal 0, pixel(hole, 10, 10)[3]
    assert_equal 255, pixel(hole, 2, 2)[3]
  end

  def test_stroke_joins_and_commands_after_close
    shape = "<path d='M4 16L10 4L16 16' fill='none' stroke='black' stroke-width='4' stroke-linejoin='%s'/>"
    miter, bevel = %w[miter bevel].map { |join| svg(shape % join).texture }
    assert_operator pixel(miter, 10, 1)[3], :>, pixel(bevel, 10, 1)[3]
    square = svg("<line x1='5' y1='10' x2='15' y2='10' stroke='black' stroke-width='4' stroke-linecap='square'/>").texture
    assert_equal 255, pixel(square, 3, 10)[3]
    after_close = svg("<path d='M2 2H8V8ZL18 18' fill-rule='evenodd' stroke='black'/>").texture
    assert_operator pixel(after_close, 16, 16)[3], :>, 0
  end

  def test_svg_rejects_active_malformed_and_unbounded_content
    assert_raises(ArgumentError) { Zaniah::SVG.new("<!DOCTYPE svg [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><svg>&e;</svg>") }
    assert_raises(ArgumentError) { svg("<script>anything</script>") }
    assert_raises(ArgumentError) { svg("<path d='M0 0 L'/>") }
    assert_raises(ArgumentError) { svg("<path d='M1e999 0'/>") }
    assert_raises(ArgumentError) { svg("<path d='M0 0 A1 1 0 2 0 1 1'/>") }
    assert_raises(ArgumentError) { svg("<rect width='-1' height='2'/>") }
    assert_raises(ArgumentError) { svg("").texture(width: 4096, height: 4096) }
  end

  def test_fenwick_prefix_and_search_against_array_oracle
    random, values = Random.new(239), Array.new(200, 24.0)
    heights = Zaniah::List::HeightIndex.new(values.length, 24)
    300.times do
      index, height = random.rand(values.length), random.rand(1..100).to_f
      values[index] = height
      heights.update(index, height)
      boundary = random.rand(0..values.length)
      assert_in_delta values.take(boundary).sum, heights.prefix(boundary), 1e-9
      y = random.rand * values.sum
      expected, sum = 0, 0
      values.each { |value| break if sum + value > y; sum += value; expected += 1 }
      assert_equal expected, heights.index_at(y)
    end
    assert_equal 0, heights.index_at(-1)
    assert_equal 200, heights.index_at(heights.total)
  end

  def context(width = 300, height = 400)
    window = Struct.new(:content_size).new(Zaniah::Size.new(width, height))
    Struct.new(:window).new(window)
  end

  def test_million_row_variable_height_list_only_constructs_visible_rows
    rendered = []
    list = Zaniah::List.new(count: 1_000_000, estimated_height: 25) do |index|
      rendered << index
      Zaniah::Div.new.h(index.even? ? 20 : 30)
    end.w(300).h(400)
    list.scroll_y = 12_500_000
    node = list.request_layout(context)
    Zaniah::Layout::Engine.new.compute(node, width: 300, height: 400)
    assert_operator rendered.length, :<, 30
    assert_includes list.visible_range, 500_000
    assert_equal list.visible_range.size, list.children.size
    assert_equal 20, list.children.find { |child| child.layout_node.bounds.height == 20 }.layout_node.bounds.height
    assert_in_delta 25_000_000, list.total_height, 30
    before = list.scroll_y
    list.update_height(2, 100)
    assert_in_delta before + 75, list.scroll_y, 1e-9
    list.scroll_to(999_999, align: :end)
    list.request_layout(context)
    assert_includes list.visible_range, 999_999
  end

  def test_list_intrinsic_heights_empty_lists_and_validation
    list = Zaniah::List.new(count: 5, estimated_height: 50) do
      Zaniah::Div.new.p(2).children([Zaniah::Div.new.h(10), Zaniah::Div.new.h(20)])
    end.h(100)
    list.request_layout(context)
    assert_equal 34, list.heights[0]
    list.scroll_to(0, align: :nearest)
    assert_equal 0, list.scroll_y
    empty = Zaniah::List.new(count: 0) { flunk "empty list rendered a row" }.h(100)
    assert_empty empty.request_layout(context).children
    assert_equal 0, empty.total_height
    assert_raises(ArgumentError) { Zaniah::List.new(count: -1) {} }
    assert_raises(ArgumentError) { Zaniah::List.new(count: 1, estimated_height: 0) {} }
    assert_raises(ArgumentError) { list.scroll_y = Float::NAN }
    assert_raises(IndexError) { list.update_height(5, 10) }
  end
end
