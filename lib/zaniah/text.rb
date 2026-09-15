# frozen_string_literal: true

module Zaniah
  class Text < Element
    InlineOverlay = Data.define(:element, :offset, :align)
    BlockOverlay = Data.define(:element, :line, :position, :height)

    attr_reader :text, :font_size, :selection, :buffer

    def initialize(text, size: 14, color: "#ddd", font: nil, wrap: :none,
      line_height: nil, letter_spacing: 0, align: :start, ellipsis: false, kinsoku: :push)
      super()
      @text, @font_size, @color, @font = text, size, color, font
      @wrap, @line_height, @letter_spacing = wrap, line_height, letter_spacing
      @text_align, @ellipsis, @kinsoku = align, ellipsis, kinsoku
      @inline_overlays, @block_overlays, @row_layout_cache = [], [], []
    end

    def measured(&block) = (@measure = block; self)
    def on_change(&block) = (@on_change = block; self)
    def placeholder(text, color: nil) = (@placeholder = text.to_s; @placeholder_color = color; self)
    def secure(value = true) = (@secure = !!value; self)
    def text_color = @color

    def inline_overlay(offset:, element:, align: :after)
      offset = Integer(offset)
      raise ArgumentError, "offset is outside the text" unless offset.between?(0, @text.bytesize)
      raise ArgumentError, "offset splits a grapheme cluster" unless Unicode.grapheme_boundary?(@text, offset)
      raise ArgumentError, "align must be before or after" unless %i[before after].include?(align)
      add_overlay(element)
      @inline_overlays << InlineOverlay.new(element, offset, align)
      @row_layout_cache[line_at(@text, offset)] = nil
      self
    end

    def block_overlay(line:, element:, position: :above, height:)
      line = Integer(line)
      height = Float(height)
      raise ArgumentError, "line is outside the text" unless line.between?(0, @text.count("\n"))
      raise ArgumentError, "position must be above or below" unless %i[above below].include?(position)
      raise ArgumentError, "height must be finite and positive" unless height.finite? && height.positive?
      add_overlay(element)
      @block_overlays << BlockOverlay.new(element, line, position, height)
      self
    end

    def remove_overlay(element)
      removed = @inline_overlays.select { |overlay| overlay.element.equal?(element) }
      @inline_overlays.reject! { |overlay| overlay.element.equal?(element) }
      @block_overlays.reject! { |overlay| overlay.element.equal?(element) }
      removed.each { |overlay| @row_layout_cache[line_at(@text, overlay.offset)] = nil }
      if @children.delete(element)
        element.send(:parent=, nil) if element.respond_to?(:parent=, true)
      end
      self
    end

    def hit_test(point)
      raise Error, "text must be laid out before coordinate conversion" unless @paragraph || @line
      @paragraph ? @paragraph.hit_test(point) : @line.index_for_x(point.x)
    end

    def offset_to_point(offset)
      raise Error, "text must be laid out before coordinate conversion" unless @paragraph || @line
      offset = Integer(offset)
      raise RangeError, "offset is outside the text" unless offset.between?(0, @text.bytesize)
      @paragraph ? @paragraph.offset_to_point(offset) : Point.new(@line.x_for_index(offset), 0)
    end

    def selection=(value)
      raise ArgumentError, "expected a TextSelection" unless value.is_a?(TextSelection)
      raise ArgumentError, "selection is outside the text" unless value.anchor <= @text.bytesize && value.head <= @text.bytesize
      raise ArgumentError, "selection splits a grapheme cluster" unless [value.anchor, value.head].all? { |offset| Unicode.grapheme_boundary?(@text, offset) }
      @selection = value
    end

    def wrap(mode = :word, line_height: @line_height, letter_spacing: @letter_spacing,
      align: @text_align, ellipsis: @ellipsis, kinsoku: @kinsoku)
      @wrap, @line_height, @letter_spacing = mode, line_height, letter_spacing
      @text_align, @ellipsis, @kinsoku = align, ellipsis, kinsoku
      self
    end

    def selectable(value = true)
      @selectable = value
      @selection ||= TextSelection.new(0)
      return self unless value
      focusable(context: {in_text_field: true}) { |action| text_action(action) }
      @focus_handle.on_input = ->(event) { text_input(event) }
      on_mouse_down { |event, _| begin_selection(event) }
      on_drag { |event, _| extend_selection(event) }
      self
    end

    def editable(buffer = nil)
      @editable = true
      @buffer = buffer || TextBuffer.new(@text)
      raise ArgumentError, "editable text requires a TextBuffer" unless @buffer.is_a?(TextBuffer)
      @text = @buffer.to_s
      selectable
    end

    def request_layout(cx)
      @text = @buffer.to_s if @buffer
      value = display_text
      @paragraph, @line = nil, nil
      overlays = !@inline_overlays.empty? || !@block_overlays.empty?
      unless overlays
        @line = cx.text_system ? cx.text_system.layout_line(value, font: @font, size: @font_size) : approximate_line(value)
      end
      line_height = @line ? @line.ascent + @line.descent : 0
      unless @wrap == :none && !@ellipsis && !overlays
        available = @style[:width]
        available = available.resolve(cx.window.content_size.width) if available.is_a?(Length)
        available = cx.window.content_size.width unless available.is_a?(Numeric)
        @paragraph = overlays ? nil : paragraph(value, available, cx.text_system)
      end
      overlay_nodes = overlay_elements.to_h do |element|
        node = element.request_layout(cx)
        raise Error, "overlay element must return a layout node" unless node.is_a?(Layout::Node)
        [element.object_id, node]
      end
      if overlays
        @paragraph = overlay_paragraph(value, available, cx.text_system, overlay_nodes)
        position_overlay_nodes(overlay_nodes)
      end
      measurement = if @measure
        lambda do |width, height|
          if overlays
            @paragraph = overlay_paragraph(value, effective_width(width), cx.text_system, overlay_nodes)
            position_overlay_nodes(overlay_nodes)
          end
          @measure.call(width, height)
        end
      elsif @wrap == :none && !@ellipsis && !overlays
        ->(_width, _height) { [@line ? @line.width : value.length * @font_size * 0.6, [@font_size * 1.4, line_height].max, @font_size] }
      else
        lambda do |width, _height|
          limit = effective_width(width)
          @paragraph = if overlays
            overlay_paragraph(value, limit, cx.text_system, overlay_nodes)
          else
            paragraph(value, limit, cx.text_system)
          end
          position_overlay_nodes(overlay_nodes) if overlays
          [@paragraph.width, @paragraph.height, @paragraph.lines.first&.layout&.ascent || @font_size]
        end
      end
      @layout_node = Layout::Node.new(style: @style, children: overlay_nodes.values, measure: measurement)
    end

    def prepaint(bounds, state, cx)
      @text_bounds = bounds
      super
    end

    def paint(bounds, state, prepaint, cx)
      super
      color = if @placeholder && @text.empty? && !@buffer&.composition
        @placeholder_color || cx.theme.colors.text_muted
      else
        @resolved_style[:text_color] || @color
      end
      paint_selection(bounds, cx) if @selectable && @selection && !@selection.collapsed?
      cx.scene.layer(Scene::LAYER_SELECTION) do
        if @paragraph
          if cx.text_system.respond_to?(:paint_paragraph)
            cx.text_system.paint_paragraph(cx.scene, @paragraph, x: bounds.x, y: bounds.y, color: color)
          elsif cx.text_system
            @paragraph.lines.each { |item| cx.text_system.paint_line(cx.scene, item.layout, x: bounds.x + item.x, y: bounds.y + item.y + item.layout.ascent, color: color) }
          end
        elsif @line && cx.text_system
          cx.text_system.paint_line(cx.scene, @line, x: bounds.x, y: bounds.y + @line.ascent, color: color)
        end
      end
      paint_composition(bounds, cx) if @buffer&.composition
      paint_caret(bounds, cx) if @editable && @selection&.collapsed? && cx.dispatcher.focused == @focus_handle
      if cx.window.respond_to?(:text_runs)
        if @paragraph
          @paragraph.lines.each { |item| cx.window.text_runs << [bounds.x + item.x, bounds.y + item.y, item.layout.text, color] }
        else
          cx.window.text_runs << [bounds.x, bounds.y, @line.text, color]
        end
      end
    end

    private

    def display_text
      value = @buffer&.composition ? @buffer.preview(@selection.head) : @text
      value = @placeholder if value.empty? && @placeholder
      @secure && !value.equal?(@placeholder) ? "*" * value.bytesize : value
    end

    def begin_selection(event)
      return if overlay_at(local_point(event.position))
      offset = offset_at(event.position)
      @selection = if event.click_count >= 3 && @paragraph
        range = @paragraph.line_range_at(offset)
        TextSelection.new(range.begin, range.end)
      elsif event.click_count == 2
        range = Unicode.word_range_at(@text, [offset, @text.bytesize].min)
        TextSelection.new(range.begin, range.end)
      else
        TextSelection.new([offset, @text.bytesize].min)
      end
    end

    def extend_selection(event)
      @selection = TextSelection.new(@selection.anchor, [offset_at(event.position), @text.bytesize].min)
    end

    def offset_at(position)
      point = local_point(position)
      hit_test(point)
    end

    def local_point(position) = Point.new(position.x - @text_bounds.x, position.y - @text_bounds.y)

    def text_action(action)
      return false unless @selection
      head = @selection.head
      case action
      when :select_all then @selection = TextSelection.new(0, @text.bytesize)
      when :move_left then @selection = TextSelection.new(@selection.collapsed? ? Unicode.previous_boundary(@text, head) : @selection.range.begin)
      when :move_right then @selection = TextSelection.new(@selection.collapsed? ? Unicode.next_boundary(@text, head) : @selection.range.end)
      when :select_left then @selection = TextSelection.new(@selection.anchor, Unicode.previous_boundary(@text, head))
      when :select_right then @selection = TextSelection.new(@selection.anchor, Unicode.next_boundary(@text, head))
      when :line_start, :select_line_start then move_to_line_edge(action, :start)
      when :line_end, :select_line_end then move_to_line_edge(action, :end)
      when :delete_backward then delete_backward
      when :delete_forward then delete_forward
      when :insert_newline then replace_selection("\n") if @editable
      else return false
      end
      true
    end

    def text_input(event)
      case event
      when Input::TextInput
        return false unless @editable
        replace_selection(event.text)
      when Input::Composition
        return false unless @editable
        @buffer.set_composition(event.text, selection: event.selection)
      else return false
      end
      true
    end

    def replace_selection(value)
      range = @selection.range
      range.begin == range.end ? @buffer.insert(range.begin, value) : @buffer.replace(range, value)
      at = range.begin + value.bytesize
      @selection = TextSelection.new(at)
      @text = @buffer.to_s
      @on_change&.call(@text)
    end

    def delete_backward
      return false unless @editable
      range = @selection.collapsed? ? Unicode.previous_boundary(@text, @selection.head)...@selection.head : @selection.range
      delete_range(range)
    end

    def delete_forward
      return false unless @editable
      range = @selection.collapsed? ? @selection.head...Unicode.next_boundary(@text, @selection.head) : @selection.range
      delete_range(range)
    end

    def delete_range(range)
      return if range.begin == range.end
      @buffer.delete(range)
      @selection = TextSelection.new(range.begin)
      @text = @buffer.to_s
      @on_change&.call(@text)
    end

    def move_to_line_edge(action, edge)
      line = @text.byteslice(0...@selection.head).count("\n")
      target = if edge == :start
        @text.split("\n", -1).take(line).sum { |value| value.bytesize + 1 }
      else
        start = @text.split("\n", -1).take(line).sum { |value| value.bytesize + 1 }
        start + (@text.split("\n", -1)[line]&.bytesize || 0)
      end
      @selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
    end

    def paint_selection(bounds, cx)
      range = @selection.range
      selection_lines.each_with_index do |(line, start, finish, x, y, height), line_index|
        first, last = [range.begin, start].max, [range.end, finish].min
        next if last <= first
        left = line.x_for_index(first - start)
        right = line.x_for_index(last - start)
        gaps = if @paragraph.respond_to?(:inline_placements)
          @paragraph.inline_placements.select { |placement| placement.line == line_index }
            .map { |placement| [placement.x - x, placement.x - x + placement.width] }
        else
          []
        end
        segments = gaps.sort.each_with_object([[left, right]]) do |(gap_start, gap_finish), values|
          segment_start, segment_finish = values.pop
          if gap_finish <= segment_start || gap_start >= segment_finish
            values << [segment_start, segment_finish]
          else
            values << [segment_start, gap_start] if gap_start > segment_start
            values << [gap_finish, segment_finish] if gap_finish < segment_finish
          end
        end
        cx.scene.layer(Scene::LAYER_SELECTION) do
          segments.each do |segment_start, segment_finish|
            next unless segment_finish > segment_start
            cx.scene.quad(bounds.x + x + segment_start, bounds.y + y,
              segment_finish - segment_start, height, color: cx.theme.colors.selection)
          end
        end
      end
    end

    def paint_caret(bounds, cx)
      offset = @selection.head + (@buffer.composition&.selection&.first || 0)
      point = point_at(offset)
      height = @paragraph ? @paragraph.lines.first.height : [@font_size * 1.4, @line ? @line.ascent + @line.descent : 0].max
      opacity = 1.0
      unless cx.theme.motion.reduced?
        animation_key = [:caret, object_id]
        unless cx.animator.animating?(animation_key)
          from = cx.animator.value(animation_key, 1.0)
          cx.animator.animate(animation_key, from: from, to: from > 0.5 ? 0.0 : 1.0, duration: 0.5, easing: :linear)
        end
        opacity = cx.animator.value(animation_key, 1.0)
      end
      cx.scene.layer(Scene::LAYER_FOCUS_RING) do
        cx.scene.quad(bounds.x + point.x, bounds.y + point.y, 1, height,
          color: @resolved_style[:text_color] || @color, opacity: opacity)
      end
      cx.window.ime_state = Bounds.new(bounds.x + point.x, bounds.y + point.y, 1, height)
    end

    def paint_composition(bounds, cx)
      start = @selection.head
      first, last = point_at(start), point_at(start + @buffer.composition.text.bytesize)
      cx.scene.layer(Scene::LAYER_FOCUS_RING) do
        cx.scene.underline(bounds.x + first.x, bounds.y + first.y + @font_size * 1.25,
          [last.x - first.x, 1].max, color: @resolved_style[:text_color] || @color)
      end
    end

    def point_at(offset)
      return @paragraph.offset_to_point(offset) if @paragraph
      Point.new(@line ? @line.x_for_index(offset) : 0, 0)
    end

    def selection_lines
      return @paragraph.lines.map { |item| [item.layout, item.start, item.finish, item.x, item.y, item.height] } if @paragraph
      [[@line, 0, @text.bytesize, 0, 0, [@font_size * 1.4, @line ? @line.ascent + @line.descent : 0].max]]
    end

    def approximate_line(value)
      byte, x, carets = 0, 0.0, [[0, 0.0]]
      value.grapheme_clusters.each do |cluster|
        byte += cluster.bytesize
        x += Unicode.width(cluster) * @font_size * 0.6
        carets << [byte, x]
      end
      TextSystem::LineLayout.new(value.dup.freeze, [].freeze, x, @font_size, @font_size * 0.4, @font_size, carets.freeze)
    end

    def paragraph(value, width, typesetter)
      TextSystem::Paragraph.new(value, width: width, size: @font_size, font: @font,
        wrap: @wrap, line_height: @line_height, letter_spacing: @letter_spacing,
        align: @text_align, ellipsis: @ellipsis, kinsoku: @kinsoku, typesetter: typesetter)
    end

    def add_overlay(element)
      unless element.respond_to?(:request_layout) && element.respond_to?(:prepaint) && element.respond_to?(:paint)
        raise ArgumentError, "overlay element must be renderable"
      end
      raise ArgumentError, "element is already an overlay" if overlay_elements.any? { |candidate| candidate.equal?(element) }
      child(element)
    end

    def overlay_elements = (@inline_overlays + @block_overlays).map(&:element)

    def line_at(value, offset) = value.byteslice(0...offset).count("\n")

    def effective_width(width)
      configured = @style[:width]
      width = configured.resolve(width) if configured.is_a?(Length)
      width = configured if configured.is_a?(Numeric)
      width.finite? ? [width, 0].max : Float::INFINITY
    end

    def source_rows(value)
      start = 0
      value.split("\n", -1).map do |source|
        [start, source].tap { start += source.bytesize + 1 }
      end
    end

    def overlay_paragraph(value, width, typesetter, nodes)
      engine = Layout::Engine.new
      rows = source_rows(value)
      inline = @inline_overlays.filter_map do |overlay|
        next if overlay.offset > value.bytesize
        measured = engine.measure(nodes.fetch(overlay.element.object_id), width: width, height: Float::INFINITY)
        unless measured.all? { |size| size.is_a?(Numeric) && size.finite? && !size.negative? }
          raise Error, "inline overlay must have a finite nonnegative size"
        end
        [row_at(rows, overlay.offset), overlay, measured]
      end
      inline_by_row = inline.group_by(&:first)
      blocks = @block_overlays.map do |overlay|
        start, source = rows.fetch(overlay.line)
        offset = overlay.position == :above ? start : start + source.bytesize
        block_width = width.finite? ? width : engine.measure(nodes.fetch(overlay.element.object_id),
          width: width, height: overlay.height).first
        raise Error, "block overlay must have a finite nonnegative width" unless block_width.is_a?(Numeric) && block_width.finite? && !block_width.negative?
        TextSystem::OverlayParagraph::Block.new(overlay.element.object_id, overlay.line,
          offset, block_width, overlay.height, overlay.position)
      end
      layout_key = [value, width, @font_size, @font&.object_id, @wrap, @line_height,
        @letter_spacing, @text_align, @ellipsis, @kinsoku, typesetter&.object_id,
        inline.map { |row, overlay, size| [row, overlay.element.object_id, overlay.offset, overlay.align, *size] },
        blocks.map { |block| [block.key, block.line, block.width, block.height, block.position] }]
      return @overlay_layout_cache.last if @overlay_layout_cache&.first == layout_key

      composed = rows.each_with_index.map do |(start, source), row|
        row_overlays = (inline_by_row[row] || []).map do |_target, overlay, (overlay_width, overlay_height)|
          TextSystem::Paragraph::InlineOverlay.new(overlay.element.object_id,
            overlay.offset - start, overlay_width, overlay_height, overlay.align)
        end
        key = [source, width, @font_size, @font&.object_id, @wrap, @line_height,
          @letter_spacing, @text_align, @ellipsis, @kinsoku, typesetter&.object_id,
          row_overlays.map { |overlay| [overlay.key, overlay.offset, overlay.width, overlay.height, overlay.align] }]
        cached = @row_layout_cache[row]
        unless cached && cached.first == key
          cached = [key, TextSystem::Paragraph.new(source, width: width, size: @font_size,
            font: @font, wrap: @wrap, line_height: @line_height, letter_spacing: @letter_spacing,
            align: @text_align, ellipsis: @ellipsis, kinsoku: @kinsoku, typesetter: typesetter,
            inline_overlays: row_overlays)]
          @row_layout_cache[row] = cached
        end
        TextSystem::OverlayParagraph::Row.new(cached.last, start)
      end
      @row_layout_cache.slice!(rows.length..-1) if @row_layout_cache.length > rows.length
      result = TextSystem::OverlayParagraph.new(value, rows: composed, blocks: blocks, width: width)
      @overlay_layout_cache = [layout_key, result]
      result
    end

    def row_at(rows, offset)
      following = rows.bsearch_index { |start, _source| start > offset }
      following ? following - 1 : rows.length - 1
    end

    def position_overlay_nodes(nodes)
      (@paragraph.inline_placements + @paragraph.block_placements).each do |placement|
        node = nodes.fetch(placement.key)
        node.style = node.style.merge(position: :absolute, left: placement.x, top: placement.y,
          width: placement.width, height: placement.height)
      end
    end

    def overlay_at(point)
      return unless @paragraph.respond_to?(:block_placements)
      (@paragraph.inline_placements + @paragraph.block_placements).find do |placement|
        Bounds.new(placement.x, placement.y, placement.width, placement.height).contains?(point)
      end
    end
  end
end
