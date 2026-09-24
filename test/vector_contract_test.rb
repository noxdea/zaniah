# frozen_string_literal: true

require_relative "test_helper"
require "zaniah/vector"
require "zaniah/svg"
require "stringio"

class VectorContractTest < Minitest::Test
  V = Zaniah::Vector

  def test_offscreen_recording_and_frame_reset
    document = V.record(width: 40, height: 30) { Zaniah::Div.new.w(10).h(10).bg("#f00") }
    assert_equal [40, 30], [document.width, document.height]
    assert_instance_of V::Quad, document.commands.first
    assert document.commands.frozen?

    window = Zaniah::Platform.open_window(width: 40, height: 30)
    recorder = V::Recorder.new
    window.scene.vector_sink = recorder
    window.render(Zaniah::Div.new.w(10).h(10).bg("#f00"))
    window.render(Zaniah::Div.new.w(10).h(10).bg("#00f"))
    assert_equal 1, recorder.document.commands.count { |command| command.is_a?(V::Quad) }
    assert_equal Zaniah::Color.parse("#00f"), recorder.document.commands.first.fill
  ensure
    window&.close
  end

  def test_vector_metadata_glyphs_and_bitmap_fallback
    scene = Zaniah::Scene.new
    recorder = V::Recorder.new(width: 20, height: 20)
    scene.vector_sink = recorder
    scene.clip(Zaniah::Bounds.new(1, 2, 12, 13)) do
      scene.layer(7) do
        scene.push_transform(Zaniah::Transform.translate(3, 4)) do
          scene.push_opacity(0.5) do
            scene.quad(0, 0, 5, 5, color: "#f00")
            scene.path("M0 0H4V4H0Z", fill: "#0f0")
            scene.underline(1, 5, 5, color: "#fff", wave: true)
            scene.shadow(1, 1, 3, 3, blur: 2)
          end
        end
      end
    end
    commands = recorder.document.commands
    assert_equal [V::Quad, V::Path, V::Underline, V::Shadow], commands.map(&:class)
    assert_equal [0, 1, 2, 3], commands.map(&:sequence)
    assert commands.all? { |command| command.layer == 7 && command.opacity == 0.5 }
    assert commands.all? { |command| command.clip == Zaniah::Bounds.new(1, 2, 12, 13) }
    assert_equal Zaniah::Transform.translate(3, 4), commands.first.transform

    texture = Zaniah::GPU::Texture.new(1, 1, data: "\xff\x00\x00\xff".b)
    scene.sprite(0, 0, 1, 1, texture: texture)
    raster = recorder.document.commands.find { |command| command.is_a?(V::Raster) }
    assert_instance_of V::Raster, raster
    texture.upload(0, 0, 1, 1, "\x00\xff\x00\xff".b)
    assert_equal "\xff\x00\x00\xff".b, raster.pixels

    radii, widths = [1, 1, 1, 1], [1, 1, 1, 1]
    scene.quad(0, 0, 4, 4, color: "#fff", radius: radii, border_width: widths)
    refute radii.frozen?
    refute widths.frozen?
  end

  def test_text_image_and_svg_paths
    window = Zaniah::Platform.open_window(width: 32, height: 32)
    window.text_system = Zaniah::TextSystem::Renderer.new
    recorder = V::Recorder.new
    window.scene.vector_sink = recorder
    window.render(Zaniah::Text.new("Hi", size: 14))
    run = recorder.document.commands.find { |command| command.is_a?(V::GlyphRun) }
    refute_nil run
    assert_equal "Hi", run.text
    assert_equal run.glyphs.length, run.clusters.length
    assert run.glyphs.all? { |id, x, y| id.is_a?(Integer) && x.is_a?(Numeric) && y.is_a?(Numeric) }
    replayed = Zaniah::Scene.new
    recorder.document.commands.each { |command| replay(replayed, command) }
    assert_equal 0, pixel_differences(window.device.pixels, Zaniah::GPU::Software.new(32, 32).render(replayed,
      clear: Zaniah::Platform::Headless::Window::DEFAULT_CLEAR))

    pixels = "\xff\x00\x00\xff".b * 4
    image = Zaniah::Image.from_bytes(Zaniah::PNG.encode(2, 2, pixels))
    window.render(image)
    captured = recorder.document.commands.find { |command| command.is_a?(V::Image) }
    assert_same image, captured.image
    assert_equal pixels, captured.pixels
    image.texture.upload(0, 0, 2, 2, "\x00\x00\xff\xff".b * 4)
    assert_equal pixels, captured.pixels

    simple = Zaniah::SVG.new("<svg width='20' height='20'><rect x='1' y='1' width='10' height='10' fill='red'/></svg>")
    window.render(simple)
    assert recorder.document.commands.any? { |command| command.is_a?(V::Path) }
    refute recorder.document.commands.any? { |command| command.is_a?(V::Raster) }
    replayed = Zaniah::Scene.new
    recorder.document.commands.each { |command| replay(replayed, command) }
    assert_equal 0, pixel_differences(window.device.pixels, Zaniah::GPU::Software.new(32, 32).render(replayed,
      clear: Zaniah::Platform::Headless::Window::DEFAULT_CLEAR))

    stroked = Zaniah::SVG.new("<svg width='20' height='20'><path d='M2 10H18' fill='none' stroke='blue' stroke-width='3' stroke-linecap='round'/></svg>")
    window.render(stroked)
    stroke = recorder.document.commands.find { |command| command.is_a?(V::Path) }
    assert_equal :round, stroke.stroke_cap
    assert_equal Zaniah::Color.parse("#00f"), stroke.stroke
    refute recorder.document.commands.any? { |command| command.is_a?(V::Raster) }
    replayed = Zaniah::Scene.new
    recorder.document.commands.each { |command| replay(replayed, command) }
    assert_equal 0, pixel_differences(window.device.pixels, Zaniah::GPU::Software.new(32, 32).render(replayed,
      clear: Zaniah::Platform::Headless::Window::DEFAULT_CLEAR))

    clipped = Zaniah::SVG.new("<svg width='20' height='20'><defs><clipPath id='c'><rect width='10' height='10'/></clipPath></defs><rect width='20' height='20' clip-path='url(#c)'/></svg>")
    window.render(clipped)
    assert recorder.document.commands.any? { |command| command.is_a?(V::Raster) }
  ensure
    window&.close
  end

  def test_software_replay_matches_screen_pixels
    image = Zaniah::Image.from_bytes(Zaniah::PNG.encode(2, 2, "\x00\xff\x00\xff".b * 4))
    texture = Zaniah::GPU::Texture.new(2, 2, data: "\xff\xff\x00\xff".b * 4)
    window = Zaniah::Platform.open_window(width: 32, height: 24)
    recorder = V::Recorder.new(width: 32, height: 24)
    window.scene.vector_sink = recorder
    window.render(Zaniah::Canvas.new do |_bounds, cx|
      scene = cx.scene
      scene.quad(1, 1, 10, 8, color: "#f00")
      scene.path("M12 1H20V9H12Z", fill: "#00f")
      scene.image(22, 1, 4, 4, image: image, texture: image.texture)
      scene.sprite(2, 18, 3, 3, texture: texture)
      scene.underline(1, 13, 15, color: "#fff", thickness: 2)
      scene.shadow(22, 10, 4, 4, color: "#0008", blur: 0)
    end)
    actual = window.device.pixels.dup
    replayed = Zaniah::Scene.new
    recorder.document.commands.each { |command| replay(replayed, command) }
    assert_equal actual, Zaniah::GPU::Software.new(32, 24).render(replayed, clear: Zaniah::Platform::Headless::Window::DEFAULT_CLEAR)
  ensure
    window&.close
  end

  def test_packed_sprite_fallback_matches_software_pixels
    texture = Zaniah::GPU::Texture.new(2, 2, data: "\xff\x00\x00\xff".b * 4)
    values = Array.new(40, 0.0)
    values[0, 8] = [3, 4, 5, 5, 1, 1, 1, 1]
    values[20, 4] = [0, 0, 1, 1]
    values[31] = 2
    values[32, 6] = [1, 0, 0, 1, 0, 0]
    scene = Zaniah::Scene.new
    recorder = V::Recorder.new(width: 12, height: 12)
    scene.vector_sink = recorder
    scene.sprite_batch(values.pack("f*"), texture: texture)
    command = recorder.document.commands.fetch(0)
    assert_instance_of V::Raster, command
    replayed = Zaniah::Scene.new
    replay(replayed, command)
    assert_equal Zaniah::GPU::Software.new(12, 12).render(scene), Zaniah::GPU::Software.new(12, 12).render(replayed)
  end

  def test_tui_cells_are_recorded_as_raster
    output = StringIO.new
    window = Zaniah::Platform::TUI::Window.new(width: 64, height: 20, input: StringIO.new, output: output)
    recorder = V::Recorder.new
    window.scene.vector_sink = recorder
    window.render(Zaniah::Text.new("A"))
    raster = recorder.document.commands.find { |command| command.is_a?(V::Raster) }
    refute_nil raster
    assert_equal [64, 20, :rgba8], [raster.pixel_width, raster.pixel_height, raster.format]
    assert raster.pixels.bytes.each_slice(4).any? { |rgba| rgba.last.positive? }
    assert_includes output.string, "A"
  ensure
    window&.close
  end

  private

  def pixel_differences(left, right)
    raise "pixel buffer size differs" unless left.bytesize == right.bytesize
    left.bytes.each_slice(4).with_index.count do |rgba, index|
      rgba != right.byteslice(index * 4, 4).bytes
    end
  end

  def replay(scene, command)
    scene.layer(command.layer) do
      transform = command.is_a?(V::Path) ? Zaniah::Transform.identity : command.transform
      scene.push_transform(transform) do
        draw = lambda do
          case command
          when V::Quad
            scene.quad(*command.bounds.to_h.values, color: command.fill, radius: command.radii,
              border_width: command.border.first, border_color: command.border.last,
              border_style: command.border_style, opacity: command.opacity)
          when V::Path
            scene.push_opacity(command.opacity) do
              [[command.fill, nil], [command.stroke, command.stroke_width]].each do |color, stroke_width|
                next unless color
                bounds, texture = Zaniah::SVG.rasterize_outline(command.outline, stroke_width: stroke_width,
                  fill_rule: command.fill_rule, stroke_cap: command.stroke_cap,
                  stroke_join: command.stroke_join, stroke_miter: command.stroke_miter,
                  transform: command.transform)
                scene.sprite(*bounds.to_h.values, texture: texture, color: color) if texture
              end
            end
          when V::GlyphRun
            scene.push_opacity(command.opacity) do
              command.glyphs.each do |id, x, baseline|
                bucket = ((x - x.floor) * 4).round % 4
                bitmap = command.font.rasterize(id, size: command.size, subpixel_x: bucket / 4.0)
                next if bitmap.width.zero? || bitmap.height.zero?
                texture = Zaniah::GPU::Texture.new(bitmap.width, bitmap.height, format: :r8, data: bitmap.coverage)
                scene.sprite(x.floor + bitmap.left, baseline.floor - bitmap.top, bitmap.width, bitmap.height,
                  texture: texture, color: command.color)
              end
            end
          when V::Image
            texture = Zaniah::GPU::Texture.new(command.pixel_width, command.pixel_height, format: command.format, data: command.pixels)
            scene.push_opacity(command.opacity) { scene.sprite(*command.bounds.to_h.values, texture: texture, source: command.source) }
          when V::Underline
            scene.push_opacity(command.opacity) { scene.underline(command.x, command.y, command.width, color: command.color, thickness: command.thickness, wave: command.wave) }
          when V::Shadow
            scene.push_opacity(command.opacity) { scene.shadow(*command.bounds.to_h.values, color: command.color, blur: command.blur, radius: command.radii, spread: command.spread, inset: command.inset) }
          when V::Raster
            texture = Zaniah::GPU::Texture.new(command.pixel_width, command.pixel_height, format: command.format, data: command.pixels)
            scene.push_opacity(command.opacity) { scene.sprite(*command.bounds.to_h.values, texture: texture, color: command.color, source: command.source) }
          end
        end
        command.clip ? scene.clip(command.clip, &draw) : draw.call
      end
    end
  end
end
