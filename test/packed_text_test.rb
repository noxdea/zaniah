# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/zaniah/gpu/instance_packing"
require "alhena"

class PackedTextTest < Minitest::Test
  def setup
    @font = Alhena::Font.open(File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__))
    @system = Zaniah::TextSystem::Renderer.new(font: @font, font_db: Zaniah::TextSystem::FontDB.new(paths: []))
  end
  def teardown = @system.close

  def packed_sprite(texture, color: "#fff", x: 1)
    scene = Zaniah::Scene.new
    scene.sprite(x, 1, 6, 6, texture: texture, color: color)
    Zaniah::GPU::InstancePacking.pack(scene).first
  end

  def test_cached_line_reuses_immutable_gpu_bytes_and_preserves_flat_api
    line = @system.layout_line("Abc", size: 16)
    first, second = Zaniah::Scene.new, Zaniah::Scene.new
    @system.paint_line(first, line, x: 1, y: 20)
    @system.paint_line(second, line, x: 1, y: 20)
    assert_same first.sprite_batches.first.bytes, second.sprite_batches.first.bytes
    assert first.sprite_batches.first.bytes.frozen?
    assert_empty first.sprite_data
    before = Zaniah::GPU::InstancePacking.pack(first)
    assert_equal 3 * 13, first.sprites.length
    assert_equal before, Zaniah::GPU::InstancePacking.pack(first)
    assert_equal 3, before.last.first.last
    assert_equal line.text.bytesize, line.index_for_x(line.width + 1)
    first.clear
    assert_empty first.sprites
    assert_empty first.sprite_batches
    assert_empty first.commands
  end

  def test_packed_and_ordinary_sprite_instances_match_exactly
    texture = Zaniah::GPU::Texture.new(2, 2, format: :r8, data: "\xff" * 4)
    bytes = packed_sprite(texture, color: "#f008")
    scene = Zaniah::Scene.new
    scene.sprite_batch(bytes, texture: texture)
    scene.sprite(1, 1, 6, 6, texture: texture, color: "#f008")
    packed, batches = Zaniah::GPU::InstancePacking.pack(scene)
    assert_equal bytes * 2, packed
    assert_equal 1, batches.length
    assert_equal 2, batches.first.last
    assert_raises(ArgumentError) { scene.sprite_batch("bad", texture: texture) }
    assert_raises(ArgumentError) { scene.sprite_batch(bytes, texture: nil) }
  end

  def test_clip_layer_and_alpha_order_match_software_reference
    texture = Zaniah::GPU::Texture.new(1, 1, data: [255, 255, 255, 255].pack("C4"))
    packed = Zaniah::Scene.new
    reference = Zaniah::Scene.new
    [packed, reference].each do |scene|
      scene.layer(2) do
        scene.clip(Zaniah::Bounds.new(0, 0, 5, 8)) do
          if scene.equal?(packed)
            scene.sprite_batch(packed_sprite(texture, color: "#f008"), texture: texture)
          else
            scene.sprite(1, 1, 6, 6, texture: texture, color: "#f008")
          end
        end
      end
      scene.layer(1) { scene.quad(0, 0, 8, 8, color: "#00f") }
      scene.layer(3) { scene.quad(2, 2, 1, 1, color: "#0f0") }
    end
    device = Zaniah::GPU::Software.new(8, 8)
    actual = device.render(packed).dup
    expected = device.render(reference).dup
    assert_equal expected, actual
    assert_equal [0, 255, 0, 255], actual.byteslice((2 * 8 + 2) * 4, 4).bytes
    assert_equal [0, 0, 255, 255], actual.byteslice((3 * 8 + 6) * 4, 4).bytes
    bytes, batches = Zaniah::GPU::InstancePacking.pack(packed)
    assert_equal %i[quad sprite quad], batches.map { |batch| batch.first.first }
    assert_equal [0, 1, 2], batches.map { |batch| batch[1] }
    assert_equal 3 * 96, bytes.bytesize
    device.release
  end

  def test_cache_invalidates_for_color_spans_position_scale_and_atlas_generation
    line = @system.layout_line("A", size: 16)
    paint = lambda do |**options|
      scene = Zaniah::Scene.new
      @system.paint_line(scene, line, x: 1, y: 20, **options)
      scene
    end
    first = paint.call
    spans = [[0, 1, "#f00"]]
    red = paint.call(spans: spans)
    spans[0][2] = "#00f"
    blue = paint.call(spans: spans)
    assert_equal [1.0, 0.0, 0.0, 1.0], red.sprites[4, 4]
    assert_equal [0.0, 0.0, 1.0, 1.0], blue.sprites[4, 4]
    moved = paint.call(x: 10)
    assert_in_delta first.sprites[0] + 9, moved.sprites[0], 0.001
    @system.scale_factor = 2
    retina = paint.call
    refute_same first.sprite_batches.first.bytes, retina.sprite_batches.first.bytes
    assert_operator retina.sprites[11], :>, first.sprites[11]
    previous_texture = retina.textures.first
    @system.atlas.send(:reset)
    replaced = paint.call
    refute_same previous_texture, replaced.textures.first
    refute_same retina.sprite_batches.first.bytes, replaced.sprite_batches.first.bytes
  end

  def test_color_font_batch_keeps_original_rgba_without_tinting
    original_tables = @font.tables
    @font.define_singleton_method(:tables) { original_tables.merge("COLR" => [0, 0]) }
    @font.define_singleton_method(:color_bitmap) do |*, **|
      Alhena::ColorBitmap.new(width: 1, height: 1, top: 1, rgba: [255, 64, 0, 255].pack("C4"))
    end
    line = @system.layout_line("A", size: 16)
    scene = Zaniah::Scene.new
    @system.paint_line(scene, line, x: 0, y: 1, color: "#00f")
    assert_equal :rgba8, scene.sprite_batches.first.texture.format
    assert_equal [1.0] * 4, scene.sprites[4, 4]
    assert_equal 2.0, scene.sprite_batches.first.bytes.unpack("f*")[17]
    device = Zaniah::GPU::Software.new(2, 2)
    assert_equal [255, 64, 0, 255], device.render(scene).byteslice(0, 4).bytes
    device.release
  end

  def test_paint_cache_capacity_and_zero_glyph_lines
    small = Zaniah::TextSystem::Renderer.new(font: @font, font_db: Zaniah::TextSystem::FontDB.new(paths: []), capacity: 2)
    scene = Zaniah::Scene.new
    %w[A B C].each { |text| small.paint_line(scene, small.layout_line(text), x: 0, y: 20) }
    assert_equal 2, small.instance_variable_get(:@paint_cache).length
    assert_operator small.instance_variable_get(:@paint_bytes), :<=, Zaniah::TextSystem::Renderer::MAX_PAINT_BYTES
    blank = Zaniah::Scene.new
    small.paint_line(blank, small.layout_line(""), x: 0, y: 20)
    assert_empty blank.commands
    small.close
  end

  def test_warm_ten_thousand_glyph_frame_has_constant_allocation_budget
    texts = Array.new(100) { |i| (format("%03d", i) + "Abcdefghij" * 10).byteslice(0, 100).freeze }
    spans = Array.new(10) { |i| [i * 10, (i + 1) * 10, %w[#f00 #0f0 #00f][i % 3]].freeze }.freeze
    scene = Zaniah::Scene.new
    frame = lambda do
      scene.clear
      texts.each_with_index do |text, i|
        @system.paint_line(scene, @system.layout_line(text), x: 2, y: 14 + i * 16, spans: spans)
      end
      Zaniah::GPU::InstancePacking.pack(scene)
    end
    3.times { frame.call }
    before = GC.stat(:total_allocated_objects)
    bytes, batches = frame.call
    allocated = GC.stat(:total_allocated_objects) - before
    assert_equal 10_000 * 96, bytes.bytesize
    assert_equal 1, batches.length
    budget = if Gem.win_platform?
      RUBY_VERSION.start_with?("3.1.") ? 2_000 : 1_500
    else
      RUBY_VERSION.start_with?("3.1.") ? 400 : 200
    end
    assert_operator allocated, :<, budget
  end
end
