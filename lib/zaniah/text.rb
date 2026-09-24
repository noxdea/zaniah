# frozen_string_literal: true

module Zaniah
  class Text < Element
    InlineOverlay = Data.define(:element, :offset, :align)
    BlockOverlay = Data.define(:element, :line, :position, :height)

    attr_reader :text, :font_size, :selection, :buffer

    def initialize(text, size: 14, color: "#ddd", font: nil, wrap: :none,
      line_height: nil, letter_spacing: 0, align: :start, ellipsis: false, kinsoku: :push,
      text_direction: :auto, caret_movement: :visual, writing_mode: :horizontal_tb,
      text_orientation: :mixed)
      super()
      raise ArgumentError, "text direction must be auto, ltr, or rtl" unless %i[auto ltr rtl].include?(text_direction)
      raise ArgumentError, "caret movement must be visual or logical" unless %i[visual logical].include?(caret_movement)
      raise ArgumentError, "writing mode must be horizontal_tb or vertical_rl" unless %i[horizontal_tb vertical_rl].include?(writing_mode)
      raise ArgumentError, "text orientation must be mixed or upright" unless %i[mixed upright].include?(text_orientation)
      @text, @font_size, @color, @font = text, size, color, font
      @wrap, @line_height, @letter_spacing = wrap, line_height, letter_spacing
      @text_align, @ellipsis, @kinsoku = align, ellipsis, kinsoku
      @text_direction, @caret_movement, @caret_affinity = text_direction, caret_movement, :downstream
      @writing_mode, @text_orientation = writing_mode, text_orientation
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
      hit_test_with_affinity(point).first
    end

    def hit_test_with_affinity(point)
      raise Error, "text must be laid out before coordinate conversion" unless @paragraph || @line
      offset, affinity = @paragraph ? @paragraph.hit_test_with_affinity(point) : @line.hit_test(point.x)
      [display_to_logical_offset(offset), affinity]
    end

    def offset_to_point(offset, affinity: :downstream)
      raise Error, "text must be laid out before coordinate conversion" unless @paragraph || @line
      offset = Integer(offset)
      raise RangeError, "offset is outside the text" unless offset.between?(0, @text.bytesize)
      raise ArgumentError, "offset splits a grapheme cluster" unless Unicode.grapheme_boundary?(@text, offset)
      display_offset = logical_to_display_offset(offset)
      @paragraph ? @paragraph.offset_to_point(display_offset, affinity: affinity) : Point.new(@line.caret_x(display_offset, affinity: affinity), 0)
    end

    def selection=(value)
      raise ArgumentError, "expected a TextSelection" unless value.is_a?(TextSelection)
      raise ArgumentError, "selection is outside the text" unless value.anchor <= @text.bytesize && value.head <= @text.bytesize
      raise ArgumentError, "selection splits a grapheme cluster" unless [value.anchor, value.head].all? { |offset| Unicode.grapheme_boundary?(@text, offset) }
      @selection = value
      @caret_affinity = :downstream
    end

    def wrap(mode = :word, line_height: @line_height, letter_spacing: @letter_spacing,
      align: @text_align, ellipsis: @ellipsis, kinsoku: @kinsoku)
      @wrap, @line_height, @letter_spacing = mode, line_height, letter_spacing
      @text_align, @ellipsis, @kinsoku = align, ellipsis, kinsoku
      @focus_handle.context[:multiline] = mode != :none || @text.include?("\n") if @focus_handle
      self
    end

    def selectable(value = true)
      @selectable = value
      @selection ||= TextSelection.new(0)
      return self unless value
      focusable(context: {in_text_field: true, multiline: @wrap != :none || @text.include?("\n")},
        validate: ->(action) { validate_text_action(action) }) { |action| text_action(action) }
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
      @cx = cx
      @text = @buffer.to_s if @buffer
      value = display_text
      @paragraph, @line = nil, nil
      overlays = !@inline_overlays.empty? || !@block_overlays.empty?
      unless overlays || @writing_mode == :vertical_rl
        @line = if cx.text_system
          if @text_direction == :auto
            cx.text_system.layout_line(value, font: @font, size: @font_size)
          else
            params = cx.text_system.method(:layout_line).parameters
            kwargs = {font: @font, size: @font_size}
            kwargs[:direction] = @text_direction if params.include?([:key, :direction]) || params.any? { |kind, _| kind == :keyrest }
            cx.text_system.layout_line(value, **kwargs)
          end
        else
          approximate_line(value)
        end
      end
      line_height = @line ? @line.ascent + @line.descent : 0
      rtl = @text_direction == :rtl || (@text_direction == :auto && !value.ascii_only? &&
        Unicode::Bidi.resolve(value, direction: :auto).direction == :rtl)
      unless @wrap == :none && !@ellipsis && !overlays && !rtl && @writing_mode != :vertical_rl
        extent = @writing_mode == :vertical_rl ? cx.window.content_size.height : cx.window.content_size.width
        available = @style[@writing_mode == :vertical_rl ? :height : :width]
        available = available.resolve(extent) if available.is_a?(Length)
        available = extent unless available.is_a?(Numeric)
        @paragraph = overlays ? nil : paragraph(value, available, cx.text_system)
      end
      overlay_nodes = overlay_elements.to_h do |element|
        node = element.request_layout(cx)
        raise Error, "overlay element must return a layout node" unless node.is_a?(Layout::Node)
        [element.object_id, node]
      end
      overlay_styles = overlay_nodes.transform_values(&:style)
      if overlays
        @paragraph = overlay_paragraph(value, available, cx.text_system, overlay_nodes, overlay_styles)
        position_overlay_nodes(overlay_nodes, overlay_styles)
      end
      measurement = if @measure
        lambda do |width, height|
          if overlays
            @paragraph = overlay_paragraph(value, effective_width(width), cx.text_system, overlay_nodes, overlay_styles)
            position_overlay_nodes(overlay_nodes, overlay_styles)
          end
          @measure.call(width, height)
        end
      elsif @wrap == :none && !@ellipsis && !overlays && @writing_mode != :vertical_rl
        ->(_width, _height) { [@line ? @line.width : value.length * @font_size * 0.6, [@font_size * 1.4, line_height].max, @font_size] }
      else
        lambda do |width, height|
          limit = @writing_mode == :vertical_rl ? effective_inline_height(height) : effective_width(width)
          @paragraph = if overlays
            overlay_paragraph(value, limit, cx.text_system, overlay_nodes, overlay_styles)
          else
            paragraph(value, limit, cx.text_system)
          end
          position_overlay_nodes(overlay_nodes, overlay_styles) if overlays
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
      value = @secure && !value.equal?(@placeholder) ? "*" * value.bytesize : value
      value.ascii_only? && value.encoding != Encoding::UTF_8 ? value.encode(Encoding::UTF_8) : value
    end

    def begin_selection(event)
      return if overlay_at(local_point(event.position))
      offset, @caret_affinity = hit_test_with_affinity(local_point(event.position))
      @selection = if event.click_count >= 3 && @paragraph
        range = @paragraph.line_range_at(logical_to_display_offset(offset))
        TextSelection.new(display_to_logical_offset(range.begin), display_to_logical_offset(range.end))
      elsif event.click_count == 2
        range = Unicode.word_range_at(@text, [offset, @text.bytesize].min)
        TextSelection.new(range.begin, range.end)
      else
        TextSelection.new([offset, @text.bytesize].min)
      end
    end

    def extend_selection(event)
      offset, @caret_affinity = hit_test_with_affinity(local_point(event.position))
      @selection = TextSelection.new(@selection.anchor, [offset, @text.bytesize].min)
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
      when :copy then @cx.window.clipboard = @text.byteslice(@selection.range)
      when :cut
        @cx.window.clipboard = @text.byteslice(@selection.range)
        delete_range(@selection.range)
      when :paste then replace_selection(@cx.window.clipboard.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace))
      when :undo, :redo then history(action)
      when :move_left, :move_right, :select_left, :select_right
        step = action.to_s.end_with?("left") ? -1 : 1
        target = @paragraph.is_a?(TextSystem::Paragraph) && @paragraph.writing_mode == :vertical_rl ?
          vertical_column_offset(head, step) : move_caret(head, step)
        @selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
      when :word_left, :word_right, :select_word_left, :select_word_right
        direction = action.to_s.end_with?("left") ? :left : :right
        target = Unicode.word_boundary(@text, head, direction)
        @selection = action.to_s.start_with?("select") ? TextSelection.new(@selection.anchor, target) : TextSelection.new(target)
      when :line_up, :line_down
        target = if @paragraph.is_a?(TextSystem::Paragraph) && @paragraph.writing_mode == :vertical_rl
          move_caret(head, action == :line_up ? -1 : 1)
        else
          Unicode.neighbor_line_offset(@text, head, action == :line_up ? -1 : 1)
        end
        @selection = TextSelection.new(target)
      when :document_start then @selection = TextSelection.new(0)
      when :document_end then @selection = TextSelection.new(@text.bytesize)
      when :line_start, :select_line_start then move_to_line_edge(action, :start)
      when :line_end, :select_line_end then move_to_line_edge(action, :end)
      when :delete_backward then delete_backward
      when :delete_forward then delete_forward
      when :insert_newline then replace_selection("\n") if @editable
      else return false
      end
      @cx&.window&.request_frame
      true
    end

    def validate_text_action(action)
      case action
      when :copy then !@secure && !@selection.collapsed?
      when :cut then !!@editable && !@secure && !@selection.collapsed?
      when :paste then !!@editable && !@buffer.composition
      when :undo then !!@editable && !@buffer.composition && @buffer.can_undo?
      when :redo then !!@editable && @buffer.can_redo?
      when :delete_backward, :delete_forward, :insert_newline then !!@editable
      when :select_all, :move_left, :move_right, :select_left, :select_right,
        :word_left, :word_right, :select_word_left, :select_word_right,
        :line_up, :line_down, :document_start, :document_end,
        :line_start, :line_end, :select_line_start, :select_line_end then true
      end
    end

    def move_caret(head, step)
      logical = -> { step.negative? ? Unicode.previous_boundary(@text, head) : Unicode.next_boundary(@text, head) }
      return logical.call if @caret_movement == :logical || @buffer&.composition
      vertical = @paragraph.is_a?(TextSystem::Paragraph) && @paragraph.writing_mode == :vertical_rl
      rows = if @paragraph
        @paragraph.lines.map { |item| [item.layout, item.start, vertical ? item.x : item.y] }
      elsif @line
        [[@line, 0, 0]]
      else
        []
      end
      return logical.call unless rows.any? { |layout, _, _| layout.visual_carets }
      entries = rows.flat_map do |layout, start, y|
        (layout.visual_carets || layout.carets.map { |byte, x| [byte, :downstream, x] })
          .map { |byte, affinity, x| [display_to_logical_offset(start + byte), affinity, x, y] }
      end
      boundaries = Unicode.grapheme_boundaries(@text).to_h { |byte| [byte, true] }
      entries.select! { |byte, _, _, _| boundaries[byte] }
      entries.sort_by! { |_, _, x, column| vertical ? [-column, x] : [column, x] }
      entries.uniq! { |byte, _, x, y| [byte, x, y] }
      position = entries.index { |byte, affinity, _, _| byte == head && affinity == @caret_affinity } ||
        entries.index { |byte, _, _, _| byte == head }
      return logical.call unless position
      target = entries[(position + step).clamp(0, entries.length - 1)]
      @caret_affinity = target[1]
      target[0]
    end

    def vertical_column_offset(head, step)
      display_head = logical_to_display_offset(head)
      point = @paragraph.offset_to_point(display_head, affinity: @caret_affinity)
      line = @paragraph.lines.find { |item| display_head.between?(item.start, item.finish) } || @paragraph.lines.last
      x = step.negative? ? line.x - 1 : line.x + line.height + 1
      display, @caret_affinity = @paragraph.hit_test_with_affinity(Point.new(x, point.y))
      display_to_logical_offset(display)
    end

    def history(action)
      before = @buffer.to_s
      @buffer.public_send(action)
      @text = @buffer.to_s
      return if @text == before
      position = Unicode.grapheme_boundaries(@text).reverse.find { |offset| offset <= @selection.head } || 0
      @selection = TextSelection.new(position)
      @on_change&.call(@text)
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
      if @paragraph.is_a?(TextSystem::Paragraph) && @paragraph.writing_mode == :vertical_rl
        cx.scene.layer(Scene::LAYER_SELECTION) do
          @paragraph.selection_rects(range).each do |rect|
            cx.scene.quad(bounds.x + rect.x, bounds.y + rect.y, rect.width, rect.height,
              color: cx.theme.colors.selection)
          end
        end
        return
      end
      selection_lines.each_with_index do |(line, start, finish, x, y, height), line_index|
        first, last = [range.begin, start].max, [range.end, finish].min
        next if last <= first
        rectangles = line.selection_rects((first - start)...(last - start))
        gaps = if @paragraph.respond_to?(:inline_placements)
          @paragraph.inline_placements.select { |placement| placement.line == line_index }
            .map { |placement| [placement.x - x, placement.x - x + placement.width] }
        else
          []
        end
        cx.scene.layer(Scene::LAYER_SELECTION) do
          rectangles.each do |rect|
            segments = [[rect.x, rect.x + rect.width]]
            gaps.sort.each do |gap_start, gap_finish|
              segments = segments.flat_map do |segment_start, segment_finish|
                if gap_finish <= segment_start || gap_start >= segment_finish
                  [[segment_start, segment_finish]]
                else
                  [[segment_start, gap_start], [gap_finish, segment_finish]].select { |a, b| b > a }
                end
              end
            end
            segments.each do |segment_start, segment_finish|
              next unless segment_finish > segment_start
              cx.scene.quad(bounds.x + x + segment_start, bounds.y + y,
                segment_finish - segment_start, height, color: cx.theme.colors.selection)
            end
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
        if @paragraph.is_a?(TextSystem::Paragraph) && @paragraph.writing_mode == :vertical_rl
          cx.scene.quad(bounds.x + point.x, bounds.y + point.y, height, 1,
            color: @resolved_style[:text_color] || @color, opacity: opacity)
        else
          cx.scene.quad(bounds.x + point.x, bounds.y + point.y, 1, height,
            color: @resolved_style[:text_color] || @color, opacity: opacity)
        end
      end
      cx.window.ime_state = if @paragraph.is_a?(TextSystem::Paragraph) && @paragraph.writing_mode == :vertical_rl
        Bounds.new(bounds.x + point.x, bounds.y + point.y, height, 1)
      else
        Bounds.new(bounds.x + point.x, bounds.y + point.y, 1, height)
      end
    end

    def paint_composition(bounds, cx)
      start = @selection.head
      first, last = point_at(start), point_at(start + @buffer.composition.text.bytesize)
      cx.scene.layer(Scene::LAYER_FOCUS_RING) do
        if @paragraph.is_a?(TextSystem::Paragraph) && @paragraph.writing_mode == :vertical_rl
          cx.scene.quad(bounds.x + first.x + @font_size * 1.25, bounds.y + [first.y, last.y].min,
            1, [(last.y - first.y).abs, 1].max, color: @resolved_style[:text_color] || @color)
        else
          cx.scene.underline(bounds.x + [first.x, last.x].min, bounds.y + first.y + @font_size * 1.25,
            [(last.x - first.x).abs, 1].max, color: @resolved_style[:text_color] || @color)
        end
      end
    end

    def point_at(offset)
      return @paragraph.offset_to_point(offset, affinity: @caret_affinity) if @paragraph
      Point.new(@line ? @line.caret_x(offset, affinity: @caret_affinity) : 0, 0)
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
        align: @text_align, ellipsis: @ellipsis, kinsoku: @kinsoku, typesetter: typesetter,
        direction: @text_direction, writing_mode: @writing_mode, text_orientation: @text_orientation)
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

    def effective_inline_height(height)
      configured = @style[:height]
      height = configured.resolve(height) if configured.is_a?(Length)
      height = configured if configured.is_a?(Numeric)
      height.finite? ? [height, 0].max : Float::INFINITY
    end

    def source_rows(value)
      start = 0
      value.split("\n", -1).map do |source|
        [start, source].tap { start += source.bytesize + 1 }
      end
    end

    def overlay_paragraph(value, width, typesetter, nodes, styles)
      engine = Layout::Engine.new
      rows = source_rows(value)
      logical_rows = source_rows(@text)
      logical_boundaries = Unicode.grapheme_boundaries(@text)
      inline = @inline_overlays.filter_map do |overlay|
        next if logical_boundaries.bsearch { |offset| offset >= overlay.offset } != overlay.offset
        display_offset = logical_to_display_offset(overlay.offset, after_insertion: overlay.align == :after)
        node = nodes.fetch(overlay.element.object_id)
        node.style = styles.fetch(overlay.element.object_id) unless node.style.equal?(styles.fetch(overlay.element.object_id))
        measured = engine.measure(node, width: width, height: Float::INFINITY)
        unless measured.all? { |size| size.is_a?(Numeric) && size.finite? && !size.negative? }
          raise Error, "inline overlay must have a finite nonnegative size"
        end
        [row_at(rows, display_offset), overlay, display_offset, measured]
      end
      inline_by_row = inline.group_by(&:first)
      blocks = @block_overlays.filter_map do |overlay|
        next unless (logical_row = logical_rows[overlay.line])
        start, source = logical_row
        logical_offset = overlay.position == :above ? start : start + source.bytesize
        offset = logical_to_display_offset(logical_offset, after_insertion: overlay.position == :below)
        line = row_at(rows, offset)
        node = nodes.fetch(overlay.element.object_id)
        node.style = styles.fetch(overlay.element.object_id) unless node.style.equal?(styles.fetch(overlay.element.object_id))
        block_width = width.finite? ? width : engine.measure(node, width: width, height: overlay.height).first
        raise Error, "block overlay must have a finite nonnegative width" unless block_width.is_a?(Numeric) && block_width.finite? && !block_width.negative?
        TextSystem::OverlayParagraph::Block.new(overlay.element.object_id, line,
          offset, block_width, overlay.height, overlay.position)
      end
      layout_key = [value.dup.freeze, width, @font_size, @font&.object_id, @wrap, @line_height,
        @letter_spacing, @text_align, @ellipsis, @kinsoku, typesetter&.object_id,
        inline.map { |row, overlay, offset, size| [row, overlay.element.object_id, offset, overlay.align, *size] },
        blocks.map { |block| [block.key, block.line, block.width, block.height, block.position] }]
      return @overlay_layout_cache.last if @overlay_layout_cache&.first == layout_key

      composed = rows.each_with_index.map do |(start, source), row|
        row_overlays = (inline_by_row[row] || []).map do |_target, overlay, offset, (overlay_width, overlay_height)|
          TextSystem::Paragraph::InlineOverlay.new(overlay.element.object_id,
            offset - start, overlay_width, overlay_height, overlay.align)
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

    def position_overlay_nodes(nodes, styles)
      placements = (@paragraph.inline_placements + @paragraph.block_placements).to_h { |placement| [placement.key, placement] }
      nodes.each do |key, node|
        unless (placement = placements[key])
          node.style = styles.fetch(key).merge(position: :absolute, display: :none)
          next
        end
        node = nodes.fetch(placement.key)
        node.style = styles.fetch(key).merge(position: :absolute, left: placement.x, top: placement.y,
          width: placement.width, height: placement.height)
      end
    end

    def logical_to_display_offset(offset, after_insertion: false)
      return 0 if @placeholder && @text.empty? && !@buffer&.composition
      composition = @buffer&.composition
      return offset unless composition
      insertion = @selection.head
      offset > insertion || (after_insertion && offset == insertion) ? offset + composition.text.bytesize : offset
    end

    def display_to_logical_offset(offset)
      return 0 if @placeholder && @text.empty? && !@buffer&.composition
      if (composition = @buffer&.composition)
        insertion = @selection.head
        offset = if offset <= insertion
          offset
        elsif offset <= insertion + composition.text.bytesize
          insertion
        else
          offset - composition.text.bytesize
        end
      end
      offset = offset.clamp(0, @text.bytesize)
      return offset if Unicode.grapheme_boundary?(@text, offset)
      before, after = Unicode.previous_boundary(@text, offset), Unicode.next_boundary(@text, offset)
      offset - before <= after - offset ? before : after
    end

    def overlay_at(point)
      return unless @paragraph.respond_to?(:block_placements)
      (@paragraph.inline_placements + @paragraph.block_placements).find do |placement|
        Bounds.new(placement.x, placement.y, placement.width, placement.height).contains?(point)
      end
    end
  end
end
