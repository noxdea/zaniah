# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "alhena"
require_relative "../lib/zaniah/text_system/atlas_cache"
require_relative "../lib/zaniah/gpu/instance_packing"

class AtlasCacheTest < Minitest::Test
  FONT_PATH = File.expand_path("../assets/fonts/Abel-Regular.ttf", __dir__)
  FONT_ID = "a" * 64

  class CountingRaster
    attr_reader :calls, :cache_key
    def initialize(version = "fixture-raster-v1")
      @calls, @cache_key = 0, version
    end
    def rasterize(font, glyph, **options)
      @calls += 1
      font.rasterize(glyph, **options)
    end
  end

  def setup
    @directory = Dir.mktmpdir("zaniah-atlas-test-")
    @systems = []
  end
  def teardown
    @systems.each(&:close)
    FileUtils.remove_entry(@directory)
  end
  def system(font: Alhena::Font.open(FONT_PATH), raster: CountingRaster.new, cache_dir: @directory)
    result = Zaniah::TextSystem::Renderer.new(font: font, font_raster: raster, cache_dir: cache_dir,
      font_db: Zaniah::TextSystem::FontDB.new(paths: []))
    @systems << result
    [result, raster]
  end
  def paint(system, text = "AB A", x: 0, size: 14)
    scene = Zaniah::Scene.new
    system.paint_line(scene, system.layout_line(text, size: size), x: x, y: 20)
    scene
  end
  def sample_atlas(format = :r8)
    atlas = Zaniah::TextSystem::Atlas.new(width: 16, height: 16, format: format)
    bytes = "\x80" * (format == :r8 ? 6 : 24)
    bitmap = format == :r8 ? Alhena::Bitmap.new(width: 2, height: 3, coverage: bytes, left: -1, top: 2) :
      Alhena::ColorBitmap.new(width: 2, height: 3, rgba: bytes, left: -1, top: 2)
    atlas.fetch([FONT_ID, 12, 14.0, 0]) { bitmap }
    atlas
  end
  def rewrite_metadata(path)
    bytes = File.binread(path)
    length = bytes.byteslice(12, 4).unpack1("N")
    metadata = JSON.parse(bytes.byteslice(52, length))
    yield metadata
    pixels = bytes.byteslice(52 + length..)
    json = JSON.generate(metadata)
    File.binwrite(path, bytes.byteslice(0, 12) + [json.bytesize, pixels.bytesize].pack("N2") +
      Digest::SHA256.new.update(json).update(pixels).digest + json + pixels)
  end

  def test_roundtrip_restores_both_texture_formats_and_safe_skyline_allocation
    [:r8, :rgba8].each do |format|
      original = sample_atlas(format)
      path = File.join(@directory, "#{format}.atlas")
      assert original.save_cache(path, key: "fixture")
      assert_equal 0o600, File.stat(path).mode & 0o777 unless Gem.win_platform?
      restored = Zaniah::TextSystem::Atlas.new(width: 16, height: 16, format: format)
      generation = restored.generation
      assert restored.load_cache(path, key: "fixture")
      assert_equal generation + 1, restored.generation
      assert_equal original.texture.data, restored.texture.data
      entry = restored.fetch([FONT_ID, 12, 14.0, 0]) { flunk "disk glyph should not rasterize" }
      assert_equal [-1, 2], [entry.left, entry.top]
      zero = format == :r8 ? Alhena::Bitmap.new(width: 0, height: 0, coverage: "") : Alhena::ColorBitmap.new(width: 0, height: 0, rgba: "")
      following = restored.fetch([FONT_ID, 13, 14.0, 0]) { zero }
      refute_equal [entry.x, entry.y], [following.x, following.y]
      assert_equal original.texture.data, restored.texture.data
    end
  end

  def test_fresh_font_objects_and_all_four_subpixel_buckets_reuse_prewarmer
    first, raster = system
    assert_same first, first.prewarm("AB A")
    assert_operator raster.calls, :>, 0
    expected = paint(first)
    second, fresh_raster = system
    second.prewarm("AB A")
    assert_equal 0, fresh_raster.calls
    actual = paint(second)
    assert_equal Zaniah::GPU::InstancePacking.pack(expected).first, Zaniah::GPU::InstancePacking.pack(actual).first
    assert_equal expected.textures.first.data, actual.textures.first.data
    [0, 0.25, 0.5, 0.75, 12.37].each { |x| paint(second, x: x) }
    assert_equal 0, fresh_raster.calls
    assert_equal 2, Dir[File.join(@directory, "*.atlas")].length
  end

  def test_content_size_dpi_raster_version_and_font_bytes_invalidate_disk_entries
    first, = system
    first.prewarm("AB A")
    [[:text, "ABC"], [:size, 17], [:dpi, 2], [:raster, "v2"], [:font, "changed"]].each do |kind, value|
      options = {}
      options[:raster] = CountingRaster.new(value) if kind == :raster
      options[:font] = Alhena::Font.new(File.binread(FONT_PATH) + "\0") if kind == :font
      fresh, raster = system(**options)
      fresh.scale_factor = value if kind == :dpi
      fresh.prewarm(kind == :text ? value : "AB A", size: kind == :size ? value : 14)
      assert_operator raster.calls, :>, 0, "#{kind} must invalidate cached glyphs"
    end
    original = first.send(:font_identity, first.font)
    alternate = Alhena::Font.open(FONT_PATH)
    alternate.define_singleton_method(:index) { 1 }
    refute_equal original, first.send(:font_identity, alternate), "TTC face identity"
    varied = Alhena::Font.open(FONT_PATH)
    varied.define_singleton_method(:axis_values) { {"wght" => 700} }
    refute_equal original, first.send(:font_identity, varied), "variation identity"
  end

  def test_default_is_io_free_and_prewarming_populates_real_atlas
    first, raster = system(cache_dir: nil)
    first.prewarm("AB A")
    calls = raster.calls
    assert_operator calls, :>, 0
    paint(first)
    assert_equal calls, raster.calls
    assert_empty Dir.children(@directory)
    assert_nil first.cache_dir
    assert_same first, first.prewarm
    assert_raises(ArgumentError) { system(cache_dir: "") }
    invalid = CountingRaster.new
    invalid.define_singleton_method(:cache_key) { nil }
    assert_raises(ArgumentError) { system(raster: invalid) }
  end

  def test_invalid_and_truncated_files_leave_existing_texture_unchanged
    source, target = sample_atlas, sample_atlas
    path = File.join(@directory, "invalid.atlas")
    source.save_cache(path, key: "fixture")
    valid = File.binread(path)
    texture = target.texture
    variants = ["", "wrong magic", valid.byteslice(0, 51), valid.byteslice(0...-1), valid + "trailing",
      valid.dup.tap { |bytes| bytes[8, 4] = [99].pack("N") },
      valid.dup.tap { |bytes| bytes[12, 4] = [0xffffffff].pack("N") },
      valid.dup.tap { |bytes| bytes.setbyte(bytes.bytesize - 1, 7) }]
    variants.each do |bytes|
      File.binwrite(path, bytes)
      refute target.load_cache(path, key: "fixture")
      assert_same texture, target.texture
    end
    File.binwrite(path, valid)
    refute target.load_cache(path, key: "different font/DPI")
    refute Zaniah::TextSystem::Atlas.new(width: 32, height: 16).load_cache(path, key: "fixture")
    refute Zaniah::TextSystem::Atlas.new(width: 16, height: 16, format: :rgba8).load_cache(path, key: "fixture")
  end

  def test_checksummed_but_invalid_metadata_is_bounded_and_rejected
    atlas = sample_atlas
    path = File.join(@directory, "tampered.atlas")
    changes = [->(data) { data["width"] = 0xffffffff }, ->(data) { data["rows"] = -1 },
      ->(data) { data["skyline"] = [[0, 0, 16]] }, ->(data) { data["skyline"][0][2] = 100 },
      ->(data) { data["entries"][0][1] = 999 }, ->(data) { data["entries"][0][0][2] = "NaN" },
      ->(data) { data["entries"] *= 2 }, ->(data) { data["entries"][0][0][0] = {} }]
    changes.each do |change|
      assert atlas.save_cache(path, key: "fixture")
      rewrite_metadata(path, &change)
      refute atlas.load_cache(path, key: "fixture")
    end
  end

  def test_file_and_directory_symlinks_are_not_followed_or_replaced
    skip "Windows symlink creation requires a separate privilege" if Gem.win_platform?
    atlas = sample_atlas
    original = File.join(@directory, "original")
    File.binwrite(original, "keep")
    path = File.join(@directory, "linked.atlas")
    File.symlink(original, path)
    refute atlas.save_cache(path, key: "fixture")
    refute atlas.load_cache(path, key: "fixture")
    assert File.symlink?(path)
    assert_equal "keep", File.binread(original)
    directory = File.join(@directory, "linked-directory")
    File.symlink(@directory, directory)
    refute atlas.save_cache(File.join(directory, "new.atlas"), key: "fixture")
    refute File.exist?(File.join(@directory, "new.atlas"))
  end

  def test_corrupt_startup_cache_is_rebuilt_without_losing_rendering
    original, = system
    original.prewarm("AB A")
    Dir[File.join(@directory, "*.atlas")].each { |path| File.binwrite(path, "truncated") }
    recovered, raster = system
    recovered.prewarm("AB A")
    assert_operator raster.calls, :>, 0
    assert_equal paint(original).sprites, paint(recovered).sprites
    third, fresh_raster = system
    third.prewarm("AB A")
    assert_equal 0, fresh_raster.calls
  end

  def test_color_atlas_reuse_does_not_rasterize_color_glyphs_again
    color_font = lambda do |forbid|
      font = Alhena::Font.open(FONT_PATH)
      tables = font.tables.merge("COLR" => [0, 0])
      font.define_singleton_method(:tables) { tables }
      font.define_singleton_method(:color_bitmap) do |*, **|
        raise "color glyph was unnecessarily rasterized" if forbid
        Alhena::ColorBitmap.new(width: 1, height: 1, top: 1, rgba: [255, 64, 0, 255].pack("C4"))
      end
      font
    end
    first, = system(font: color_font.call(false))
    first.prewarm("A")
    second, = system(font: color_font.call(true))
    second.prewarm("A")
    scene = paint(second, "A")
    assert_equal :rgba8, scene.textures.first.format
    device = Zaniah::GPU::Software.new(2, 22)
    assert_equal [255, 64, 0, 255], device.render(scene).byteslice(19 * 2 * 4, 4).bytes
    device.release
  end

  def test_disk_cache_is_reusable_in_a_separate_process
    original, = system(raster: :alhena)
    original.prewarm("AB A")
    code = <<~RUBY
      system = Zaniah::TextSystem::Renderer.new(cache_dir: ARGV[0],
        font_db: Zaniah::TextSystem::FontDB.new(paths: [ARGV[1]]))
      system.instance_variable_get(:@rasters).define_singleton_method(:rasterize) { |*| raise "unexpected rasterization" }
      system.prewarm("AB A")
      scene = Zaniah::Scene.new
      system.paint_line(scene, system.layout_line("AB A"), x: 12.37, y: 20)
      raise "restored scene was empty" if scene.sprite_batches.empty?
      puts "restored without rasterization"
      system.close
    RUBY
    output, error, status = Open3.capture3({"RUBYOPT" => nil, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR)}, Gem.ruby,
      "-I", File.expand_path("../lib", __dir__),
      "-r", "zaniah", "-e", code, @directory, FONT_PATH)
    assert status.success?, error
    assert_equal "restored without rasterization\n", output
  end

  def test_atomic_writers_leave_a_complete_snapshot_and_io_errors_are_misses
    atlas = sample_atlas
    path = File.join(@directory, "shared.atlas")
    writers = 2.times.map { Thread.new { 5.times.map { atlas.save_cache(path, key: "fixture") } } }
    assert writers.flat_map(&:value).all?
    assert atlas.load_cache(path, key: "fixture")
    refute atlas.load_cache(File.join(@directory, "missing"), key: "fixture")
    File.stub(:open, ->(*) { raise Errno::EACCES }) do
      refute atlas.load_cache(path, key: "fixture")
    end
    refute atlas.save_cache(@directory, key: "fixture")
    assert File.directory?(@directory)
    assert_empty Dir.children(@directory).grep(/\.tmp\z/)
  end

  def test_multiple_prewarm_sizes_preserve_entries_in_either_restore_order
    original, = system
    original.prewarm("AB A", size: 14)
    original.prewarm("AB A", size: 16)
    [[16, 14], [14, 16]].each do |sizes|
      restored, raster = system
      sizes.each { |size| restored.prewarm("AB A", size: size) }
      [14, 16].each { |size| paint(restored, size: size, x: 0.75) }
      assert_equal 0, raster.calls, "restoring #{sizes.inspect} must preserve both warm sizes"
    end
  end
end
