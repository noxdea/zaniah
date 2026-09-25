# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class FrameworkTest < Minitest::Test
  T = Zaniah

  def test_geometry_and_color
    assert_equal T::Bounds.new(5, 5, 5, 5), T::Bounds.new(0, 0, 10, 10).intersect(T::Bounds.new(5, 5, 10, 10))
    assert_equal [1, 0, 0, 1], T::Color.parse("#f00").to_a
    assert_equal [1, 0, 0, 0.5], T::HSLA.new(0, 1, 0.5, 0.5).to_rgba.to_a
    T::Color.parse("#3699").to_a.zip(T::Color.parse("#3699").to_hsla.to_rgba.to_a).each { |a, b| assert_in_delta a, b }
    assert_equal 75, T.percent(25).resolve(300)
  end

  def test_alpha_order_clip_rounding_and_png
    scene = T::Scene.new
    scene.quad(0, 0, 10, 10, color: "#f00")
    scene.clip(T::Bounds.new(5, 0, 5, 10)) { scene.quad(0, 0, 10, 10, color: [0, 0, 1, 0.5]) }
    device = T::GPU::Software.new(10, 10)
    data = device.render(scene)
    assert_equal [255, 0, 0, 255], data.byteslice(0, 4).bytes
    assert_equal [128, 0, 128, 255], data.byteslice(6 * 4, 4).bytes
    width, height, decoded = T::PNG.decode(T::PNG.encode(10, 10, data))
    assert_equal [10, 10, data], [width, height, decoded]
    assert_raises(ArgumentError) { T::PNG.decode(T::PNG.encode(10, 10, data).tap { |s| s.setbyte(50, s.getbyte(50) ^ 1) }) }
    scene.clear.quad(0, 0, 10, 10, color: "#fff", radius: 5)
    rounded = device.render(scene)
    assert_equal 0, rounded.getbyte(3)
    assert_equal 255, rounded.getbyte((5 * 10 + 5) * 4 + 3)
  end

  def test_headless_scale_factor_preserves_logical_layout_and_scales_pixels
    scene = T::Scene.new.quad(0, 0, 4, 2, color: "#f00")
    scene.clip(T::Bounds.new(1, 0, 1, 2)) { scene.quad(0, 0, 4, 2, color: "#0f0") }
    device = T::GPU::Software.new(4, 2, scale_factor: 2)
    pixels = device.render(scene)
    assert_equal [8, 4], [device.width, device.height]
    assert_equal [255, 0, 0, 255], pixels.byteslice(0, 4).bytes
    assert_equal [0, 255, 0, 255], pixels.byteslice(2 * 4, 4).bytes
    assert_equal [255, 0, 0, 255], pixels.byteslice(4 * 4, 4).bytes
    assert_raises(ArgumentError) { device.resize(100_000, 100_000) }
    assert_equal [8, 4], [device.width, device.height]

    window = T::Platform::Headless::Window.new(width: 4, height: 2, scale_factor: 2)
    assert_equal [4, 2], [window.content_size.width, window.content_size.height]
    assert_equal [8, 4], [window.device.width, window.device.height]
    assert_raises(ArgumentError) { window.resize(100_000, 100_000) }
    assert_equal [4, 2], [window.content_size.width, window.content_size.height]
  ensure
    window&.close
  end

  def test_sprite_and_gpu_frame_contract
    device = T::GPU::Software.new(2, 1)
    texture = device.create_texture(2, 1, format: :r8, data: [0, 255].pack("C*"))
    scene = T::Scene.new.sprite(0, 0, 2, 1, texture: texture, color: "#0f0")
    assert_equal [0, 0, 0, 0, 0, 255, 0, 255], device.render(scene).bytes
    buffer = device.create_buffer(T::Scene::QUAD_STRIDE * 4)
    q = T::Scene.new.quad(0, 0, 2, 1, color: "#ff0")
    buffer.write(q.quads.pack("f*"))
    frame = device.begin_frame
    frame.set_pipeline(device.create_pipeline(shader: :quad))
    frame.draw_instanced(vertex_count: 4, instance_buffer: buffer, instance_count: 1)
    assert_equal [255, 255, 0, 255] * 2, frame.present.bytes
    assert_raises(ArgumentError) { texture.upload(1, 0, 2, 1, "xx") }
  end

  %i[row column row_reverse column_reverse].each do |direction|
    [100, 120, 160, 200, 240, 300, 400, 500, 640, 800, 960, 1024, 1200].each do |space|
      define_method("test_flex_#{direction}_#{space}") do
        row = direction.to_s.start_with?("row")
        dimension = row ? :width : :height
        first = T::Layout::Node.new(style: {dimension => 20, flex_shrink: 0})
        second = T::Layout::Node.new(style: {flex_grow: 1, flex_basis: 0})
        root = T::Layout::Node.new(style: {flex_direction: direction}, children: [first, second])
        T::Layout::Engine.new.compute(root, width: space, height: space)
        assert_in_delta 20, row ? first.bounds.width : first.bounds.height
        assert_in_delta space - 20, row ? second.bounds.width : second.bounds.height
        coordinate = row ? first.bounds.x : first.bounds.y
        assert_in_delta(direction.to_s.end_with?("reverse") ? space - 20 : 0, coordinate)
      end
    end
  end

  def test_flex_limits_wrapping_absolute_and_cache_invalidation
    root = T::Layout::Node.new(style: {flex_direction: :row, padding: 10, gap: 10})
    first = root.add(T::Layout::Node.new(style: {flex_grow: 1, max_width: 30}))
    last = root.add(T::Layout::Node.new(style: {flex_grow: 1}))
    absolute = root.add(T::Layout::Node.new(style: {position: :absolute, width: T.percent(50), height: 5, right: 0, top: 0}))
    engine = T::Layout::Engine.new
    engine.compute(root, width: 200, height: 100)
    assert_equal 30, first.bounds.width
    assert_equal 140, last.bounds.width
    assert_equal T::Bounds.new(100, 10, 90, 5), absolute.bounds
    first.style = first.style.merge(max_width: 50)
    engine.compute(root, width: 200, height: 100)
    assert_equal 50, first.bounds.width
    assert_equal 120, last.bounds.width
  end

  def test_leaf_layout_updates_bounds_without_populating_the_container_cache
    leaf = T::Layout::Node.new
    engine = T::Layout::Engine.new

    engine.compute(leaf, width: 20, height: 10)
    assert_equal T::Bounds.new(0, 0, 20, 10), leaf.bounds
    assert_empty leaf.cache

    engine.compute(leaf, width: 30, height: 15)
    assert_equal T::Bounds.new(0, 0, 30, 15), leaf.bounds
    assert_empty leaf.cache
  end

  def test_default_flex_fast_path_matches_general_layout
    %i[row column row_reverse column_reverse].each do |direction|
      build = lambda do |margin|
        children = [
          T::Layout::Node.new(style: {width: 10, height: 20, flex_grow: 1, margin: margin}),
          T::Layout::Node.new(style: {width: 20, height: 10, flex_grow: 2, margin: margin})
        ]
        T::Layout::Node.new(style: {flex_direction: direction, gap: 3}, children: children)
      end
      fast, general = build.call(0), build.call(T.px(0))
      engine = T::Layout::Engine.new
      simple_flow = engine.method(:layout_simple_flow)
      fast_path_used = false
      engine.define_singleton_method(:layout_simple_flow) { |*args| fast_path_used = true; simple_flow.call(*args) }
      engine.compute(fast, width: 40, height: 25)
      T::Layout::Engine.new.compute(general, width: 40, height: 25)
      assert fast_path_used, direction
      assert_equal general.children.map(&:bounds), fast.children.map(&:bounds), direction
    end
  end

  def test_default_flex_shrink_never_crosses_minimum
    children = [
      T::Layout::Node.new(style: {width: 7, height: 24, flex_grow: 1, flex_shrink: 0}),
      T::Layout::Node.new(style: {width: 42, height: 5, flex_grow: 3, flex_shrink: 3}),
      T::Layout::Node.new(style: {width: 34, height: 31, flex_grow: 3, flex_shrink: 2})
    ]
    root = T::Layout::Node.new(style: {flex_direction: :column_reverse, gap: 1}, children: children)
    T::Layout::Engine.new.compute(root, width: 138, height: 7)
    assert_equal [24, 0, 0], children.map { |child| child.bounds.height }
  end

  def test_nested_entities_observation_and_disposal
    app = T::App.new
    source = app.new_entity { [] }
    events = []
    owner = app.new_entity do |cx|
      cx.observe(source) { |_, value, _| events << value.dup }
      []
    end
    source.update(app) do |value, cx|
      value << 1
      cx.notify
      source.update(app) { |inner, nested| inner << 2; nested.notify }
      assert_empty events
    end
    assert_equal [[1, 2]], events
    owner.release(app)
    source.update(app) { |value, cx| value << 3; cx.notify }
    assert_equal 1, events.length
    replacement = app.new_entity { :new }
    assert_equal owner.id, replacement.id
    assert_raises(T::Error) { owner.read(app) }
    assert_equal 2, app.entity_count
  ensure
    app&.executor&.shutdown
  end

  def test_executor_and_cancellation
    executor = T::TaskExecutor.new(workers: 1)
    assert_equal 42, executor.background { 6 * 7 }.await(timeout: 2)
    task = executor.spawn { 12 }
    executor.drain
    assert_equal 12, task.await
    cancelled = executor.spawn { flunk "cancelled task ran" }
    cancelled.cancel
    executor.drain
    assert_raises(T::Task::Cancelled) { cancelled.await }
  ensure
    executor&.shutdown
  end

  def test_headless_pipeline_and_virtualization
    window = T::Platform.open_window(width: 200, height: 100)
    window.title = "Virtualized list"
    assert_equal "Virtualized list", window.title
    count = 0
    list = T::UniformList.new(count: 1_000_000, row_height: 20) { |i| count += 1; T::Text.new(i.to_s) }
    list.scroll_y = 4_000
    window.draw { list }
    window.tick
    assert_equal 6, count
    assert_equal(200...206, list.visible_range)
    refute window.dirty?
    window.tick
    assert_equal 6, count
    window.close
    assert window.closed?
  end

  def test_element_hit_and_frame_inspection
    window = T::Platform.open_window(width: 200, height: 100)
    text = T::Text.new("Save", size: 16, color: "#abc")
    root = T::Div.new.test_id("save").on_click {}.child(text)
    frame = nil
    window.on_frame { |element, clear| frame = [element, clear] }
    window.render(root)

    assert_equal "save", root.test_id
    assert_equal [:click], root.handlers
    assert root.handlers.frozen?
    assert_equal ["Save", 16, "#abc"], [text.text, text.font_size, text.text_color]
    assert_same root, window.dispatcher.hits.last.owner
    assert_equal [root, T::Platform::Headless::Window::DEFAULT_CLEAR], frame
  ensure
    window&.close
  end

  30.times do |i|
    define_method("test_context_expression_#{i}") do
      p = T::Input::ContextPredicate.new("Editor && (vim_mode == normal || count == #{i}) && !Menu")
      assert p.call(Editor: true, vim_mode: "insert", count: i)
      refute p.call(Editor: false, vim_mode: "normal", count: i)
      refute p.call(Editor: true, vim_mode: "normal", Menu: true)
    end
  end

  def test_key_sequences_and_no_expression_evaluation
    keys = T::Input::Keymap.new.bind("ctrl-k ctrl-s", :save).bind("cmd-s", :save)
    assert_equal :pending, keys.dispatch("control-k", now: 1)
    assert_equal :save, keys.dispatch("ctrl-s", now: 1.1)
    keys.dispatch("ctrl-k", now: 2)
    assert_nil keys.dispatch("ctrl-s", now: 4)
    assert_equal :save, keys.dispatch("super-s", now: 5)
    assert_raises(ArgumentError) { T::Input::ContextPredicate.new('Editor; system("echo nope")') }
  end
end
