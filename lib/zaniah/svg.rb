# frozen_string_literal: true

require "rexml/document"

module Zaniah
  # Static vector icons. No scripting, external resources, or browser engine.
  class SVG < Element
    IDENTITY = [1, 0, 0, 1, 0, 0].freeze
    DEFAULTS = {"fill" => "black", "stroke" => "none", "stroke-width" => "1",
      "fill-rule" => "nonzero", "fill-opacity" => "1", "stroke-opacity" => "1",
      "stroke-linecap" => "butt", "stroke-linejoin" => "miter", "stroke-miterlimit" => "4"}.freeze
    PRESENTATION = (DEFAULTS.keys + %w[color opacity display visibility clip-path clip-rule]).freeze
    ELEMENTS = %w[svg g path rect circle ellipse line polyline polygon defs use clipPath title desc metadata].freeze
    NAMES = {"black" => "#000", "white" => "#fff", "red" => "#f00", "green" => "#008000",
      "blue" => "#00f", "yellow" => "#ff0", "gray" => "#808080", "grey" => "#808080",
      "silver" => "#c0c0c0", "maroon" => "#800000", "purple" => "#800080", "fuchsia" => "#f0f",
      "lime" => "#0f0", "olive" => "#808000", "navy" => "#000080", "teal" => "#008080",
      "aqua" => "#0ff", "orange" => "#ffa500", "transparent" => "#0000", "rebeccapurple" => "#639"}.freeze
    attr_reader :width, :height, :view_box

    def self.parse(source, **options) = new(source, **options)
    def self.open(path, **options) = new(File.binread(path), **options)

    def initialize(source, color: "#000")
      super()
      require "alhena"
      raise ArgumentError, "SVG exceeds 2 MiB" if source.bytesize > 2 * 1024 * 1024
      raise ArgumentError, "SVG document types and entities are forbidden" if source.match?(/<!\s*(?:DOCTYPE|ENTITY)/i)
      @root = REXML::Document.new(source).root
      raise ArgumentError, "expected an SVG root" unless @root&.name == "svg"
      @ids, @paths, @textures, @color = {}, {}, {}, color
      validate(@root, 0, [0])
      @view_box = numbers(@root.attributes["viewBox"]) if @root.attributes["viewBox"]
      if @view_box && (@view_box.length != 4 || !@view_box[2].positive? || !@view_box[3].positive?)
        raise ArgumentError, "viewBox must contain x y width height with positive dimensions"
      end
      @width = length(@root.attributes["width"], @view_box ? @view_box[2] : 300, percentage: true)
      @height = length(@root.attributes["height"], @view_box ? @view_box[3] : 150, percentage: true)
      raise ArgumentError, "SVG dimensions must be positive" unless @width.positive? && @height.positive?
      @view_box ||= [0, 0, @width, @height]
    rescue REXML::ParseException => error
      raise ArgumentError, "invalid SVG: #{error.message.lines.first}"
    end

    def request_layout(_cx)
      @layout_node = Layout::Node.new(style: @style, measure: ->(_w, _h) { [@width, @height] })
    end

    def paint(bounds, _state, _pre, cx)
      return if bounds.width <= 0 || bounds.height <= 0
      scale = cx.window.respond_to?(:scale_factor) ? cx.window.scale_factor : 1
      raster = texture(width: (bounds.width * scale).ceil, height: (bounds.height * scale).ceil)
      cx.scene.sprite(bounds.x, bounds.y, bounds.width, bounds.height, texture: raster)
    end

    def texture(width: @width.ceil, height: @height.ceil, color: @color)
      unless width.is_a?(Integer) && height.is_a?(Integer) && width.positive? && height.positive? && width * height <= 1_048_576
        raise ArgumentError, "SVG raster dimensions must be positive and at most 1 megapixel"
      end
      key = [width, height, color]
      return @textures[key] if @textures.key?(key)
      pixels = "\0".b * (width * height * 4)
      render(@root, pixels, viewport(width, height), DEFAULTS.merge("color" => color), width, height, [])
      @textures.shift if @textures.length >= 8
      @textures[key] = GPU::Texture.new(width, height, data: pixels)
    end

    private

    def validate(element, depth, count)
      count[0] += 1
      raise ArgumentError, "SVG tree is too complex" if depth > 64 || count[0] > 10_000
      raise ArgumentError, "unsupported SVG element #{element.name}" unless ELEMENTS.include?(element.name)
      raise ArgumentError, "nested SVG viewports are not supported" if depth.positive? && element.name == "svg"
      %w[filter mask stroke-dasharray marker-start marker-mid marker-end].each do |attribute|
        raise ArgumentError, "unsupported SVG attribute #{attribute}" if element.attributes[attribute]
      end
      @ids[element.attributes["id"]] = element if element.attributes["id"]
      @paths[element] = geometry(element) if %w[path rect circle ellipse line polyline polygon].include?(element.name)
      element.elements.each { |child| validate(child, depth + 1, count) }
    end

    def number(value)
      text = value.to_s.strip
      raise ArgumentError, "invalid SVG number #{value.inspect}" unless text.match?(/\A#{Path::NUMBER}\z/)
      result = Float(text)
      raise ArgumentError, "SVG number out of range" unless result.finite? && result.abs <= 1e9
      result
    end

    def numbers(value)
      scanner, result = StringScanner.new(value.to_s), []
      until scanner.eos?
        scanner.skip(/[\s,]*/)
        break if scanner.eos?
        token = scanner.scan(Path::NUMBER)
        raise ArgumentError, "invalid SVG number list" unless token
        result << number(token)
      end
      result
    end

    def length(value, fallback = 0, percentage: false)
      return fallback unless value
      text = value.to_s.strip
      if text.end_with?("%")
        raise ArgumentError, "percentage SVG geometry is not supported" unless percentage
        return number(text.delete_suffix("%")) * fallback / 100
      end
      number(text.delete_suffix("px"))
    end

    def geometry(element)
      attr = element.attributes
      get = ->(key, fallback = 0) { length(attr[key], fallback) }
      case element.name
      when "path" then Path.parse(attr["d"].to_s)
      when "line" then Alhena::Outline.new.move_to(get.call("x1"), get.call("y1")).line_to(get.call("x2"), get.call("y2"))
      when "polyline", "polygon"
        points = numbers(attr["points"])
        raise ArgumentError, "polygon needs coordinate pairs" if points.length.odd?
        outline = Alhena::Outline.new
        points.each_slice(2).with_index { |point, i| outline.public_send(i.zero? ? :move_to : :line_to, *point) }
        outline.close if element.name == "polygon" && !outline.empty?
        outline
      when "circle", "ellipse"
        cx, cy = get.call("cx"), get.call("cy")
        rx, ry = element.name == "circle" ? [get.call("r")] * 2 : [get.call("rx"), get.call("ry")]
        raise ArgumentError, "negative ellipse radius" if rx.negative? || ry.negative?
        return Alhena::Outline.new if rx.zero? || ry.zero?
        Path.parse("M#{cx + rx} #{cy} A#{rx} #{ry} 0 1 1 #{cx - rx} #{cy} A#{rx} #{ry} 0 1 1 #{cx + rx} #{cy}Z")
      when "rect"
        x, y, w, h = get.call("x"), get.call("y"), get.call("width"), get.call("height")
        raise ArgumentError, "negative rectangle size" if w.negative? || h.negative?
        return Alhena::Outline.new if w.zero? || h.zero?
        rx, ry = get.call("rx", get.call("ry")), get.call("ry", get.call("rx"))
        raise ArgumentError, "negative rectangle radius" if rx.negative? || ry.negative?
        rx, ry = [rx, w / 2].min, [ry, h / 2].min
        if rx.zero? || ry.zero?
          Alhena::Outline.new.move_to(x, y).line_to(x + w, y).line_to(x + w, y + h).line_to(x, y + h).close
        else
          Path.parse("M#{x + rx} #{y}H#{x + w - rx}A#{rx} #{ry} 0 0 1 #{x + w} #{y + ry}V#{y + h - ry}A#{rx} #{ry} 0 0 1 #{x + w - rx} #{y + h}H#{x + rx}A#{rx} #{ry} 0 0 1 #{x} #{y + h - ry}V#{y + ry}A#{rx} #{ry} 0 0 1 #{x + rx} #{y}Z")
        end
      end
    end

    def multiply(left, right)
      a, b, c, d, e, f = left
      g, h, i, j, k, l = right
      [a * g + c * h, b * g + d * h, a * i + c * j, b * i + d * j, a * k + c * l + e, b * k + d * l + f]
    end

    def transform(source)
      scanner, matrix = StringScanner.new(source.to_s), IDENTITY
      until scanner.eos?
        scanner.skip(/[\s,]*/)
        break if scanner.eos?
        name = scanner.scan(/[a-zA-Z]+/)
        scanner.skip(/\s*/)
        raise ArgumentError, "invalid SVG transform" unless name && scanner.scan(/\(/)
        values = scanner.scan(/[^)]*/)
        raise ArgumentError, "unclosed SVG transform" unless scanner.scan(/\)/)
        values = numbers(values)
        operation = case name
        when "matrix" then values if values.length == 6
        when "translate" then [1, 0, 0, 1, values[0], values.fetch(1, 0)] if (1..2).cover?(values.length)
        when "scale" then [values[0], 0, 0, values.fetch(1, values[0]), 0, 0] if (1..2).cover?(values.length)
        when "rotate"
          if [1, 3].include?(values.length)
            angle = values[0] * Math::PI / 180
            rotation = [Math.cos(angle), Math.sin(angle), -Math.sin(angle), Math.cos(angle), 0, 0]
            values.length == 1 ? rotation : multiply(multiply([1, 0, 0, 1, values[1], values[2]], rotation), [1, 0, 0, 1, -values[1], -values[2]])
          end
        when "skewX", "skewY"
          if values.length == 1
            tangent = Math.tan(values[0] * Math::PI / 180)
            name == "skewX" ? [1, 0, tangent, 1, 0, 0] : [1, tangent, 0, 1, 0, 0]
          end
        end
        raise ArgumentError, "invalid SVG transform #{name}" unless operation && operation.all?(&:finite?)
        matrix = multiply(matrix, operation)
      end
      matrix
    end

    def viewport(width, height)
      x, y, w, h = @view_box
      sx, sy = width.to_f / w, height.to_f / h
      alignment, mode = (@root.attributes["preserveAspectRatio"] || "xMidYMid meet").split
      return [sx, 0, 0, sy, -x * sx, -y * sy] if alignment == "none"
      raise ArgumentError, "invalid preserveAspectRatio" unless alignment.match?(/\Ax(Min|Mid|Max)Y(Min|Mid|Max)\z/) && [nil, "meet", "slice"].include?(mode)
      scale = mode == "slice" ? [sx, sy].max : [sx, sy].min
      ax = alignment.include?("xMin") ? 0 : (alignment.include?("xMax") ? 1 : 0.5)
      ay = alignment.include?("YMin") ? 0 : (alignment.include?("YMax") ? 1 : 0.5)
      [scale, 0, 0, scale, (width - w * scale) * ax - x * scale, (height - h * scale) * ay - y * scale]
    end

    def properties(element, inherited)
      style = inherited.reject { |key, _| %w[opacity clip-path display].include?(key) }
      PRESENTATION.each { |key| style[key] = element.attributes[key] if element.attributes[key] }
      element.attributes["style"].to_s.split(";").each do |declaration|
        key, value = declaration.split(":", 2).map(&:strip)
        next unless key && value
        raise ArgumentError, "unsupported SVG style #{key}" unless PRESENTATION.include?(key)
        style[key] = value
      end
      style.each { |key, value| style[key] = inherited.fetch(key, DEFAULTS[key]) if value == "inherit" }
      style
    end

    def render(element, pixels, matrix, inherited, width, height, references, definition: false)
      return if %w[title desc metadata].include?(element.name)
      return if %w[defs clipPath].include?(element.name) && !definition
      style = properties(element, inherited)
      return if style["display"] == "none"
      matrix = multiply(matrix, transform(element.attributes["transform"]))
      opacity = number(style.fetch("opacity", "1")).clamp(0, 1)
      isolated = opacity < 1 || style["clip-path"]
      target = isolated ? "\0".b * pixels.bytesize : pixels
      if element.name == "use"
        href = element.attributes["href"] || element.attributes["xlink:href"]
        raise ArgumentError, "SVG use must reference a local id" unless href&.start_with?("#")
        raise ArgumentError, "cyclic SVG use" if references.include?(href) || references.length >= 32
        referenced = @ids.fetch(href.delete_prefix("#")) { raise ArgumentError, "unknown SVG reference #{href}" }
        shifted = multiply(matrix, [1, 0, 0, 1, length(element.attributes["x"]), length(element.attributes["y"])])
        render(referenced, target, shifted, style, width, height, references + [href], definition: true)
      elsif (outline = @paths[element]) && style["visibility"] != "hidden"
        unless style["fill"] == "none" || outline.empty?
          paint_mask(target, mask(outline.transform(matrix), width, height, style["fill-rule"]), color(style["fill"], style["color"]), number(style["fill-opacity"]).clamp(0, 1))
        end
        unless style["stroke"] == "none" || outline.empty?
          thickness = length(style["stroke-width"])
          raise ArgumentError, "negative SVG stroke width" if thickness.negative?
          if thickness.positive?
            stroked = stroke(outline, thickness, style).transform(matrix)
            paint_mask(target, mask(stroked, width, height, "nonzero"), color(style["stroke"], style["color"]), number(style["stroke-opacity"]).clamp(0, 1))
          end
        end
      else
        element.elements.each { |child| render(child, target, matrix, style, width, height, references) }
      end
      if isolated
        if style["clip-path"] && style["clip-path"] != "none"
          id = style["clip-path"][/\Aurl\(\s*#([^\s)]+)\s*\)\z/, 1]
          clipping = @ids[id]
          raise ArgumentError, "invalid SVG clipping reference" unless clipping&.name == "clipPath"
          raise ArgumentError, "cyclic SVG clip" if references.include?(id) || references.length >= 32
          clip = clip_mask(clipping, matrix, width, height, references + [id])
          (width * height).times { |i| target.setbyte(i * 4 + 3, (target.getbyte(i * 4 + 3) * clip.getbyte(i) / 255.0).round) }
        end
        composite(pixels, target, opacity)
      end
    end

    def color(value, current)
      value = current if value == "currentColor"
      value = NAMES.fetch(value.downcase, value)
      if (match = value.match(/\Argba?\(([^)]+)\)\z/i))
        channels = match[1].split(/[\s,\/]+/)
        raise ArgumentError, "invalid SVG rgb color" unless (3..4).cover?(channels.length)
        rgba = channels.each_with_index.map { |channel, i| channel.end_with?("%") ? number(channel.delete_suffix("%")) / 100 : number(channel) / (i == 3 ? 1 : 255.0) }
        rgba << 1 if rgba.length == 3
        return rgba.map { |channel| (channel.clamp(0, 1) * 255).round }
      end
      Color.parse(value).to_a.map { |channel| (channel * 255).round }
    end

    def paint_mask(pixels, coverage, rgba, opacity)
      coverage.bytes.each_with_index do |alpha, index|
        next if alpha.zero?
        blend(pixels, index * 4, rgba[0], rgba[1], rgba[2], (alpha * rgba[3] * opacity / 255.0).round)
      end
    end

    def composite(pixels, layer, opacity)
      (pixels.bytesize / 4).times do |index|
        offset = index * 4
        blend(pixels, offset, layer.getbyte(offset), layer.getbyte(offset + 1), layer.getbyte(offset + 2), (layer.getbyte(offset + 3) * opacity).round)
      end
    end

    def blend(pixels, offset, r, g, b, alpha)
      return if alpha.zero?
      previous = pixels.getbyte(offset + 3) * (255 - alpha) / 255.0
      result = alpha + previous
      [r, g, b].each_with_index { |channel, i| pixels.setbyte(offset + i, ((channel * alpha + pixels.getbyte(offset + i) * previous) / result).round) }
      pixels.setbyte(offset + 3, result.round)
    end
  end

end

require_relative "svg/path"
require_relative "svg/rasterizable"
Zaniah::SVG.include(Zaniah::SVG::Rasterizable)
