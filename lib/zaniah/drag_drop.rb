# frozen_string_literal: true

module Zaniah
  module DragDrop
    Target = Data.define(:id, :position)
    Event = Data.define(:phase, :source_id, :target, :point, :reason)

    class Reorder
      POSITIONS = %i[before after inside].freeze

      attr_reader :source_id, :target, :announcement

      def initialize(threshold: 4, locate:, keyboard: nil, label: nil)
        @threshold = Float(threshold)
        raise ArgumentError, "drag threshold must be nonnegative" unless @threshold.finite? && @threshold >= 0
        raise ArgumentError, "a pointer target locator is required" unless locate.respond_to?(:call)
        raise TypeError, "keyboard target locator must respond to call" if keyboard && !keyboard.respond_to?(:call)
        raise TypeError, "item labeler must respond to call" if label && !label.respond_to?(:call)

        @locate, @keyboard, @label = locate, keyboard, label || ->(id) { id.to_s }
      end

      def on_event(&block) = (guard_reentry; @on_event = block; self)
      def on_drop(&block) = (guard_reentry; @on_drop = block; self)
      def on_announce(&block) = (guard_reentry; @on_announce = block; self)
      def dragging? = !!@dragging

      def press(id, point)
        guard_reentry
        validate_id(id)
        validate_point(point)
        begin
          cancel(:replaced) if @active
          @active = true
          @source_id, @pressed_at, @last_point = id, point, point
          emit(:press, point: point)
          true
        rescue StandardError => error
          recover(error)
        end
      end

      def move(point)
        guard_reentry
        return false unless @active
        validate_point(point)
        begin
          @last_point = point
          unless @dragging
            return false if distance(@pressed_at, point) < @threshold
            @dragging = true
            emit(:start, point: point)
          end
          transition(normalize_target(callback(@locate, point, @source_id)), point)
          true
        rescue StandardError => error
          recover(error)
        end
      end

      def release(point = @last_point)
        guard_reentry
        return false unless @active
        validate_point(point) if point
        begin
          move(point) if point && (!@last_point.equal?(point) || !@dragging)
          return reset(false) unless @dragging

          dropped = @target
          unless dropped
            cancel(:no_target)
            return false
          end
          source = @source_id
          message = move_announcement(source, dropped)
          event = Event.new(phase: :drop, source_id: source, target: dropped, point: point, reason: nil)
          reset
          publish(event)
          callback(@on_drop, event)
          announce(message)
          true
        rescue StandardError => error
          recover(error)
        end
      end

      def keyboard(id, direction)
        guard_reentry
        validate_id(id)
        raise ArgumentError, "keyboard reordering is not configured" unless @keyboard
        raise ArgumentError, "keyboard direction must be previous, next, or inside" unless %i[previous next inside].include?(direction)

        begin
          cancel(:replaced) if @active
          @active, @source_id, @dragging = true, id, true
          emit(:start, reason: :keyboard)
          destination = normalize_target(callback(@keyboard, id, direction))
          unless destination
            cancel(:no_target)
            return false
          end
          transition(destination, nil)
          message = move_announcement(id, destination)
          event = Event.new(phase: :drop, source_id: id, target: destination, point: nil, reason: :keyboard)
          reset
          publish(event)
          callback(@on_drop, event)
          announce(message)
          true
        rescue StandardError => error
          recover(error)
        end
      end

      def action(id, action)
        case action
        when :reorder_before then keyboard(id, :previous)
        when :reorder_after then keyboard(id, :next)
        when :reorder_inside then keyboard(id, :inside)
        when :cancel_reorder then cancel
        else false
        end
      end

      def remove(id)
        guard_reentry
        return cancel(:removed) if @source_id == id
        return false unless @target&.id == id

        begin
          emit(:leave, target: @target, point: @last_point, reason: :removed)
          @target = nil
          true
        rescue StandardError => error
          recover(error)
        end
      end

      def cancel(reason = :cancelled)
        guard_reentry
        return false unless @active

        begin
          source, destination, point = @source_id, @target, @last_point
          message = "Cancelled moving #{label(source)}" if @dragging
          events = []
          events << Event.new(phase: :leave, source_id: source, target: destination, point: point, reason: reason) if destination
          events << Event.new(phase: :cancel, source_id: source, target: destination, point: point, reason: reason)
          reset
          events.each { |event| publish(event) }
          announce(message) if message
          true
        rescue StandardError => error
          recover(error)
        end
      end

      def accessibility_node(_context = nil)
        return unless @announcement
        Accessibility.node(role: :status, label: @announcement,
          states: {live: true, revision: @announcement_revision})
      end

      private

      def transition(destination, point)
        if destination == @target
          emit(:over, target: destination, point: point) if destination
          return
        end
        emit(:leave, target: @target, point: point) if @target
        @target = destination
        emit(:enter, target: destination, point: point) if destination
      end

      def normalize_target(destination)
        return unless destination
        raise TypeError, "target locator must return a DragDrop::Target" unless destination.is_a?(Target)
        validate_id(destination.id)
        raise ArgumentError, "drop position must be before, after, or inside" unless POSITIONS.include?(destination.position)
        return if destination.id == @source_id

        destination
      end

      def emit(phase, target: @target, point: @last_point, reason: nil)
        Event.new(phase: phase, source_id: @source_id, target: target, point: point, reason: reason).tap { |event| publish(event) }
      end

      def publish(event) = (callback(@on_event, event); event)
      def move_announcement(source, destination) = "Moved #{label(source)} #{destination.position} #{label(destination.id)}"

      def announce(message)
        @announcement = message.freeze
        @announcement_revision = (@announcement_revision || 0) + 1
        callback(@on_announce, @announcement)
      end

      def label(id) = callback(@label, id).to_s
      def distance(first, second) = Math.hypot(second.x - first.x, second.y - first.y)
      def guard_reentry
        raise Error, "drag-and-drop callbacks must not re-enter their controller" if @notifying
      end

      def callback(callable, *arguments)
        return unless callable
        @notifying = true
        callable.call(*arguments)
      ensure
        @notifying = false
      end

      def validate_id(id)
        raise ArgumentError, "drag item id must not be nil" if id.nil?
      end

      def validate_point(point)
        raise TypeError, "drag position must be a Point" unless point.is_a?(Point)
      end

      def reset(result = nil)
        @active = @source_id = @pressed_at = @last_point = @target = @dragging = nil
        result
      end

      def recover(error)
        active, source, target, point = @active, @source_id, @target, @last_point
        reset
        begin
          publish(Event.new(phase: :cancel, source_id: source, target: target,
            point: point, reason: :error)) if active
        rescue StandardError
          # Preserve the first callback failure.
        end
        raise error
      end
    end
  end
end
