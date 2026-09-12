# frozen_string_literal: true

module Zaniah
  class TextBuffer
    Composition = Data.define(:text, :selection)
    attr_reader :composition

    def initialize(text = "", clock: MONOTONIC_CLOCK, group_interval: 0.75)
      validate_text(text)
      @text, @clock, @group_interval = text.dup, clock, Float(group_interval)
      raise ArgumentError, "group interval must be finite and nonnegative" unless @group_interval.finite? && !@group_interval.negative?
      @undo, @redo, @composition = [], [], nil
    end

    def to_s = @text.dup
    def bytesize = @text.bytesize

    def insert(offset, string)
      change(offset...offset, string, :insert)
    end

    def delete(range)
      change(normalize_range(range), "", :delete)
    end

    def replace(range, string)
      change(normalize_range(range), string, :replace)
    end

    def undo
      return self unless (edit = @undo.pop)
      @text = edit[:before]
      @redo << edit
      self
    end

    def redo
      return self unless (edit = @redo.pop)
      @text = edit[:after]
      @undo << edit
      self
    end

    def previous_boundary(offset) = Unicode.previous_boundary(@text, checked_offset(offset))
    def next_boundary(offset) = Unicode.next_boundary(@text, checked_offset(offset))

    def line_at(offset)
      @text.byteslice(0...checked_offset(offset)).count("\n")
    end

    def offset_at(line, column)
      raise ArgumentError, "line and column must be nonnegative integers" unless line.is_a?(Integer) && column.is_a?(Integer) && line >= 0 && column >= 0
      lines = @text.split("\n", -1)
      return @text.bytesize if line >= lines.length
      base = lines.take(line).sum { |item| item.bytesize + 1 }
      base + lines[line].grapheme_clusters.take(column).sum(&:bytesize)
    end

    def set_composition(text, selection: [text.bytesize, 0])
      validate_text(text)
      raise ArgumentError, "composition selection must contain two nonnegative integers" unless selection.is_a?(Array) && selection.length == 2 && selection.all? { |value| value.is_a?(Integer) && value >= 0 }
      @composition = text.empty? ? nil : Composition.new(text.dup.freeze, selection.dup.freeze)
      self
    end

    def clear_composition = (@composition = nil; self)

    def commit_composition(offset)
      return self unless @composition
      insert(offset, @composition.text)
    end

    def preview(offset)
      return to_s unless @composition
      offset = checked_offset(offset)
      @text.byteslice(0...offset) + @composition.text + @text.byteslice(offset..)
    end

    private

    def change(range, replacement, kind)
      validate_text(replacement)
      range = normalize_range(range)
      return self if range.begin == range.end && replacement.empty?
      before = @text.dup
      @text = @text.byteslice(0...range.begin) + replacement + @text.byteslice(range.end..)
      now = @clock.call
      last = @undo.last
      if kind == :insert && last && last[:kind] == :insert && last[:finish] == range.begin && now - last[:time] <= @group_interval
        last[:after], last[:finish], last[:time] = @text.dup, range.begin + replacement.bytesize, now
      else
        @undo << {before: before, after: @text.dup, kind: kind, finish: range.begin + replacement.bytesize, time: now}
      end
      @redo.clear
      @composition = nil
      self
    end

    def normalize_range(range)
      raise ArgumentError, "expected a Range" unless range.is_a?(Range)
      first, last = Integer(range.begin), Integer(range.end)
      last += 1 unless range.exclude_end?
      raise ArgumentError, "range is outside the buffer" unless first.between?(0, @text.bytesize) && last.between?(first, @text.bytesize)
      [first, last].each { |offset| raise ArgumentError, "offset splits a grapheme cluster" unless Unicode.grapheme_boundary?(@text, offset) }
      first...last
    end

    def checked_offset(offset)
      offset = Integer(offset)
      raise ArgumentError, "offset is outside the buffer" unless offset.between?(0, @text.bytesize)
      raise ArgumentError, "offset splits a grapheme cluster" unless Unicode.grapheme_boundary?(@text, offset)
      offset
    end

    def validate_text(text)
      raise ArgumentError, "text must be valid UTF-8" unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
    end
  end
end
