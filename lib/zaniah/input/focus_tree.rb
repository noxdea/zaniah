# frozen_string_literal: true

module Zaniah
  module Input
    class FocusTree
      def initialize
        @roots, @traps = [], []
      end

      def register(handle)
        root = handle
        root = root.parent while root.parent
        @roots << root unless @roots.include?(root)
        self
      end

      def clear = @roots.clear

      def next(from = nil) = move(from, 1)
      def previous(from = nil) = move(from, -1)

      def spatial(from, direction)
        return unless from&.bounds
        raise ArgumentError, "direction must be left, right, up, or down" unless %i[left right up down].include?(direction)
        source = from.bounds
        sx, sy = center(source)
        candidates.reject { |handle| handle.equal?(from) || !handle.bounds }.select do |handle|
          tx, ty = center(handle.bounds)
          delta = %i[left right].include?(direction) ? tx - sx : ty - sy
          %i[left up].include?(direction) ? delta.negative? : delta.positive?
        end.min_by do |handle|
          target = handle.bounds
          tx, ty = center(target)
          primary = %i[left right].include?(direction) ? tx - sx : ty - sy
          cross_gap = %i[left right].include?(direction) ? interval_gap(source.y, source.bottom, target.y, target.bottom) : interval_gap(source.x, source.right, target.x, target.right)
          [cross_gap.zero? ? 0 : 1, primary.abs, cross_gap, Math.hypot(tx - sx, ty - sy)]
        end
      end

      def trap(handle)
        @traps << handle
        return handle unless block_given?
        begin
          yield
        ensure
          restore
        end
      end

      def restore = @traps.pop

      private

      def move(from, step)
        items = candidates
        return if items.empty?
        index = items.index(from)
        items[index ? (index + step) % items.length : (step.positive? ? 0 : -1)]
      end

      def candidates
        list = []
        roots = @traps.empty? ? @roots : [@traps.last]
        visit = ->(handle) do
          list << handle if handle.focusable && !handle.tab_index.nil?
          handle.children.each(&visit)
        end
        roots.each(&visit)
        list.each_with_index.sort_by { |(handle, index)| [handle.tab_index, index] }.map!(&:first)
      end

      def center(bounds) = [bounds.x + bounds.width / 2.0, bounds.y + bounds.height / 2.0]
      def interval_gap(a1, a2, b1, b2) = [a1 - b2, b1 - a2, 0].max
    end
  end
end
