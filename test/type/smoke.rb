# frozen_string_literal: true

# Runs unchanged against source, runtime RBS hooks, and an installed gem.
# No test framework is required.
require "zaniah"
require "tmpdir"

module PublicAPISmoke
  def self.check(condition, message)
    raise message unless condition
  end

  def self.run
    library = $LOADED_FEATURES.find { |path| path.end_with?("/lib/zaniah.rb") }
    root = File.expand_path("..", File.dirname(library))
    font_path = File.join(root, "assets/fonts/Abel-Regular.ttf")
    point = Zaniah::Point.new(x: 2, y: 3)
    bounds = Zaniah::Bounds.new(0, 0, 40, 30).inset(Zaniah::Edges.all(1))
    check(bounds.contains?(point), "geometry failed")
    check(Zaniah.percent(25).resolve(40) == 10, "length failed")
    check(Zaniah::Color.parse("#369").to_hsla.to_rgba.a == 1, "color failed")
    check(Zaniah::Unicode.width("👩‍💻") == 2, "Unicode tables missing")

    tree = Zaniah::LayoutTree.new
    parent = tree.new_node(style: {flex_direction: :row})
    child = tree.new_node(style: {width: 12})
    tree.add_child(parent, child)
    tree.set_style(child, height: 7)
    tree.compute(parent, width: 40, height: 30)
    check(tree.bounds(child).width == 12, "layout failed")
    check(Zaniah::Layout::Engine.new.measure(tree.nodes[child], width: 40, height: 30) == [12, 7], "measurement failed")

    keymap = Zaniah::Input::Keymap.new.bind("ctrl-k ctrl-s", :save)
    dispatcher = Zaniah::Input::Dispatcher.new(keymap: keymap)
    focus = Zaniah::Input::FocusHandle.new(context: {Editor: true})
    actions = []
    focus.on_action = ->(action) { actions << action; true }
    dispatcher.focus(focus)
    check(dispatcher.key("ctrl-k") == :pending, "key prefix failed")
    check(dispatcher.key("ctrl-s") == :save && actions == [:save], "key dispatch failed")
    dispatcher.hit(bounds) { |_event| true }
    check(dispatcher.mouse(Zaniah::Input::MouseDown.new(point, :left, [], 1)), "mouse dispatch failed")

    window = Zaniah::Platform.open_window(width: 80, height: 60)
    check(window.displays.first.primary, "headless display metadata failed")
    font_db = Zaniah::TextSystem::FontDB.new(paths: [font_path])
    font = font_db.open(font_path)
    check(font_db.faces.first.family == "Abel", "font metadata failed")
    check(font_db.find(family: "Abel", weight: 400, width: 5, style: :normal).family == "Abel", "font selection failed")
    window.text_system = Zaniah::TextSystem::Renderer.new(font: font, font_db: font_db)
    line = window.text_system.layout_line("Ruby", size: 12)
    check(line.width.positive? && line.index_for_x(0) == 0, "font/shaper failed")
    check(line.x_for_index(4) == line.width, "byte caret failed")
    paragraph = window.text_system.layout_paragraph("Ruby wraps", width: line.width, size: 12)
    check(paragraph.lines.length > 1, "paragraph layout failed")
    text_buffer = Zaniah::TextBuffer.new("Ruby")
    text_buffer.insert(4, " UI").undo.redo
    check(text_buffer.to_s == "Ruby UI", "text buffer history failed")
    check(Zaniah::TextSelection.new(0, 4).range == (0...4), "text selection failed")
    Dir.mktmpdir("zaniah-api-atlas-") do |directory|
      cached = Zaniah::TextSystem::Renderer.new(font: font, font_db: font_db, cache_dir: directory)
      cached.prewarm("Ruby", size: 12)
      restored = Zaniah::TextSystem::Renderer.new(font: font, font_db: font_db, cache_dir: directory)
      restored.prewarm("Ruby", size: 12)
      check(cached.atlas.texture.data == restored.atlas.texture.data, "disk atlas roundtrip failed")
      cached.close
      restored.close
    end
    icon = Zaniah::SVG.parse('<svg width="8" height="8"><path fill="red" d="M0 0H8V8H0Z"/></svg>')
    check(icon.texture.width == 8, "SVG/rasterizer dependencies missing")
    root_element = Zaniah::Div.new.flex_col.p(2).bg("#123")
      .child(Zaniah::Text.new("Ruby", size: 12)).child(icon)
      .child(Zaniah::List.new(count: 50, estimated_height: 5) { |index| Zaniah::Div.new.h(5).key(index) }.h(10))
    window.draw { root_element }
    window.tick
    check(!window.dirty? && !window.scene.commands.empty?, "element pipeline failed")
    pixels = window.device.pixels
    encoded = Zaniah::PNG.encode(80, 60, pixels)
    check(Zaniah::PNG.decode(encoded) == [80, 60, pixels], "PNG roundtrip failed")

    device = Zaniah::GPU::Software.new(2, 2)
    scene = Zaniah::Scene.new.quad(0, 0, 2, 2, color: "#f00")
    scene.layer(2) { scene.clip(Zaniah::Bounds.new(0, 0, 1, 1)) { scene.quad(0, 0, 1, 1, color: "#00f") } }
    check(scene.each_command.to_a.length == 2, "scene enumeration failed")
    buffer = device.create_buffer(scene.quads.length * 4).write(Zaniah::QuadPacker.new.pack(scene))
    frame = device.begin_frame
    frame.set_pipeline(device.create_pipeline(shader: :quad))
    frame.draw_instanced(vertex_count: 4, instance_buffer: buffer, instance_count: 2)
    frame.present
    check(device.pixels.bytesize == 16, "frame encoding failed")
    texture = device.create_texture(1, 1, format: :r8).upload(0, 0, 1, 1, "\xff".b)
    check(texture.revision == 1, "texture upload failed")

    app = Zaniah::App.new
    source = app.new_entity { [] }
    notifications = []
    owner = app.new_entity do |context|
      context.observe(source) { |_owner, value, _context| notifications << value.dup }
      :owner
    end
    source.update(app) { |value, context| value << 42; context.notify }
    check(source.read(app) == [42] && notifications == [[42]], "entity observation failed")
    owner.release(app)
    task = app.executor.spawn { app.executor.background { 6 * 7 }.await(timeout: 2) }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    until task.done?
      raise "executor timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      app.executor.drain
      app.executor.wait(0.001)
    end
    check(task.await == 42, "task future failed")
    pool = Zaniah::ProcessPool.new(workers: 1, handler: "WordCountWorker",
      requires: [File.join(root, "examples/word_count_worker.rb")], max_pending: 2)
    counted = pool.submit("text" => "Ruby process pool").await(timeout: 3)
    check(counted.fetch("words") == 3 && counted.fetch("pid") != Process.pid, "spawned process pool failed")
    pool.shutdown
    source.release(app)
    check(app.entity_count.zero?, "entity release failed")
    puts "public API smoke: geometry/layout/input/elements/SVG/text/PNG/GPU/entities/tasks/processes passed"
  ensure
    pool&.shutdown
    app&.executor&.shutdown
    window&.close
    device&.release
  end
end

PublicAPISmoke.run unless ENV["ZANIAH_TYPE_DRIVER"] == "1"
