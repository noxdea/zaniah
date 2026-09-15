# frozen_string_literal: true

require_relative "test_helper"
require "alhena"

class LowResolutionTextCacheTest < Minitest::Test
  def rectangle(x, y, width, height)
    Alhena::Outline.new.move_to(x, y).line_to(x + width, y).line_to(x + width, y + height)
      .line_to(x, y + height).close
  end

  def test_generates_a_deterministic_headless_texture
    cache = Zaniah::TextSystem::LowResolutionTextCache.new(width: 4, height: 1, scale: 1)
    texture = cache.texture(7, outlines: [rectangle(0, 0, 2, 1)])
    scene = Zaniah::Scene.new.sprite(0, 0, 4, 1, texture: texture, color: "#f00")
    device = Zaniah::GPU::Software.new(4, 1)

    assert_equal :r8, texture.format
    assert_equal [255, 255, 0, 0], texture.data.bytes
    assert_equal [255, 0, 0, 255] * 2 + [0, 0, 0, 0] * 2, device.render(scene).bytes
  ensure
    cache&.close
    device&.release
  end

  def test_reuses_rows_and_invalidates_only_the_edited_line
    cache = Zaniah::TextSystem::LowResolutionTextCache.new(width: 4, height: 1, scale: 1)
    first = cache.texture(0, outlines: [rectangle(0, 0, 1, 1)])
    untouched = cache.texture(1, outlines: [rectangle(0, 0, 2, 1)])

    assert_same first, cache.texture(0, outlines: [])
    cache.invalidate(0)
    replacement = cache.texture(0, outlines: [rectangle(2, 0, 1, 1)])
    assert_equal [0, 0, 255, 0], replacement.data.bytes
    refute_same first, replacement
    assert_same untouched, cache.texture(1, outlines: [])
    assert_equal [255, 0, 0, 0], first.data.bytes
    duplicate = cache.texture(2, outlines: [rectangle(0, 0, 2, 1)])
    refute_same untouched, duplicate
    duplicate.release
    assert_equal [255, 255, 0, 0], untouched.data.bytes
    cache.close
    assert_equal [255, 255, 0, 0], untouched.data.bytes
  ensure
    cache&.close
  end

  def test_lru_and_byte_limits_bound_retained_textures
    cache = Zaniah::TextSystem::LowResolutionTextCache.new(
      width: 4, height: 1, scale: 1, capacity: 2, max_bytes: 8
    )
    first = cache.texture(0, outlines: [])
    second = cache.texture(1, outlines: [])
    assert_same first, cache.texture(0, outlines: [rectangle(0, 0, 4, 1)])
    cache.texture(2, outlines: [])

    assert_equal 2, cache.size
    assert_equal 8, cache.bytesize
    refute_same second, cache.texture(1, outlines: [])

    uncached = Zaniah::TextSystem::LowResolutionTextCache.new(
      width: 4, height: 1, scale: 1, capacity: 2, max_bytes: 3
    )
    outline = rectangle(0, 0, 1, 1)
    refute_same uncached.texture(0, outlines: [outline]), uncached.texture(0, outlines: [outline])
    assert_equal 0, uncached.size
    assert_equal 0, uncached.bytesize
    assert_nil uncached.instance_variable_get(:@last_coverage)

    released = cache.texture(3, outlines: [])
    released.release
    cache.texture(4, outlines: [])
    cache.texture(5, outlines: [])
    assert_operator cache.bytesize, :<=, cache.max_bytes
    assert_equal cache.size * 4, cache.bytesize
  ensure
    cache&.close
    uncached&.close
  end

  def test_operations_are_thread_safe_and_close_is_idempotent
    cache = Zaniah::TextSystem::LowResolutionTextCache.new(
      width: 2, height: 1, scale: 1, capacity: 4, max_bytes: 8
    )
    textures = 8.times.map do
      Thread.new { cache.texture(3, outlines: [rectangle(0, 0, 1, 1)]) }
    end.map(&:value)
    assert_equal 1, textures.uniq(&:object_id).length
    assert_equal 1, cache.size

    cache.close.close
    assert cache.closed?
    assert_equal 0, cache.bytesize
    assert_raises(Zaniah::Error) { cache.texture(3, outlines: []) }
    assert_raises(Zaniah::Error) { cache.invalidate(3) }
    assert_raises(Zaniah::Error) { cache.clear }
  end

  def test_validates_dimensions_keys_and_alhena_input
    assert_raises(ArgumentError) { Zaniah::TextSystem::LowResolutionTextCache.new(width: 0) }
    assert_raises(ArgumentError) { Zaniah::TextSystem::LowResolutionTextCache.new(width: 1, scale: Float::INFINITY) }
    assert_raises(ArgumentError) { Zaniah::TextSystem::LowResolutionTextCache.new(width: 1, scale: 10**1000) }
    assert_raises(ArgumentError) { Zaniah::TextSystem::LowResolutionTextCache.new(width: 1, scale: Rational(1, 10**1000)) }
    assert_raises(ArgumentError) { Zaniah::TextSystem::LowResolutionTextCache.new(width: 1, capacity: 0) }
    assert_raises(ArgumentError) { Zaniah::TextSystem::LowResolutionTextCache.new(width: 1, max_bytes: 0) }
    cache = Zaniah::TextSystem::LowResolutionTextCache.new(width: 1)
    assert_raises(ArgumentError) { cache.texture(-1, outlines: []) }
    assert_raises(ArgumentError) { cache.texture(0, outlines: Object.new) }
    failing = Enumerator.new { |values| values << rectangle(0, 0, 1, 1); raise "broken outlines" }
    assert_raises(RuntimeError) { cache.texture(0, outlines: failing) }
    malformed = rectangle(0, 0, 1, 1).tap { |outline| outline.coordinates[1] = Float::NAN }
    2.times { assert_raises(FloatDomainError) { cache.texture(0, outlines: [malformed]) } }
    assert_equal [0, 0], [cache.size, cache.bytesize]
    assert_equal [0, 0], cache.texture(0, outlines: []).data.bytes
  ensure
    cache&.close
  end
end
