# frozen_string_literal: true

module Zaniah
  module UI
    class PropertyGrid < Component
      Property = Data.define(:key, :label, :type, :options, :validation)
      TYPES = %i[text number boolean select color date time textarea].freeze

      attr_reader :values, :errors

      def initialize(schema, values = {}, height: 320, row_height: 52)
        super()
        @properties = Array(schema).map { |entry| normalize(entry) }.freeze
        raise ArgumentError, "property keys must be unique" unless @properties.map(&:key).uniq.length == @properties.length
        @values = values.to_h.transform_keys(&:to_sym)
        @height, @row_height = Float(height), Float(row_height)
        raise ArgumentError, "property grid dimensions must be positive" unless @height.positive? && @row_height.positive?
        @controls, @drafts, @errors, @selected_index = {}, {}, {}, 0
      end

      def on_change(&block) = (@on_change = block; self)

      def set(key, value)
        property = @properties.find { |entry| entry.key == key.to_sym }
        return false unless property
        errors = Array(property.validation.validate(value)).map(&:to_s)
        if errors.empty?
          @errors.delete(property.key)
          @drafts.delete(property.key)
          return false if @values[property.key] == value
          @values[property.key] = value
          @controls.delete(property.key) unless @editing_key == property.key
          @on_change&.call(property.key, value, @values.dup.freeze, @cx)
        else
          @errors[property.key] = errors.freeze
          @drafts[property.key] = value
        end
        @cx&.window&.request_frame
        errors.empty?
      end

      def build(cx)
        @cx = cx
        @list ||= List.new(count: @properties.length, estimated_height: @row_height, overscan: 2) { |index| row(index, @cx) }
        @list.h(@height).focusable(context: {in_table: true}) { |action| table_action(action) }
        Div.new.h(@height).overflow_hidden.border(1).border_color(cx.theme.colors.border)
          .rounded(cx.theme.radii[:sm]).child(@list)
      end

      def tui_cells(*)
        @properties.first(20).map do |property|
          "#{property.label}: #{@values[property.key]}#{@errors.key?(property.key) ? " ! #{@errors[property.key].join(', ')}" : ''}"
        end.join("\n")
      end

      def accessibility_node(cx)
        range = @list&.visible_range
        range = 0...[@properties.length, (@height / @row_height).ceil + 2].min if !range || range.size.zero?
        children = range.map do |index|
          property = @properties[index]
          control = @controls[property.key]&.accessibility_node(cx)
          error = @errors[property.key]
          Accessibility.node(role: :row, id: [:property, property.key].freeze,
            states: {selected: index == @selected_index, invalid: !!error},
            children: [Accessibility.node(role: :rowheader, label: property.label),
              Accessibility.node(role: :cell, value: @drafts.fetch(property.key) { @values[property.key] },
                children: [control, (Accessibility.node(role: :alert, label: error.join(", ")) if error)].compact)])
        end
        node(:table, states: {size: @properties.length}, children: children)
      end

      private

      def normalize(entry)
        entry = {key: entry} if entry.is_a?(String) || entry.is_a?(Symbol)
        raise ArgumentError, "property schema entries must be hashes or names" unless entry.is_a?(Hash)
        key = entry.fetch(:key).to_sym
        type = entry.fetch(:type, :text).to_sym
        raise ArgumentError, "unknown property type #{type}" unless TYPES.include?(type)
        options = entry.fetch(:options, [])
        validation = entry.fetch(:validation, Validation.new)
        raise ArgumentError, "validation must respond to validate" unless validation.respond_to?(:validate)
        Property.new(key: key, label: entry.fetch(:label, key.to_s).to_s,
          type: type, options: options, validation: validation)
      end

      def row(index, cx)
        property = @properties.fetch(index)
        unless @controls.key?(property.key)
          @controls.shift if @controls.size >= 128
          @controls[property.key] = control_for(property)
        end
        control = @controls[property.key]
        label = Label.new(property.label, size: :sm)
        cell = Div.new.flex_1.child(control)
        root = Div.new.key(property.key).flex_row.items_center.gap(cx.theme.spacing[3]).min_h(@row_height)
          .p([4, 8]).border_b(1).border_color(cx.theme.colors.border)
          .bg(index == @selected_index ? cx.theme.colors.selection : "#0000")
          .child(Div.new.w(140).child(label)).child(cell)
        root.child(Label.new(@errors[property.key].first, tone: :muted, size: :xs)) if @errors.key?(property.key)
        root
      end

      def control_for(property)
        key, value, label = property.key, @drafts.fetch(property.key) { @values[property.key] }, property.label
        control = case property.type
        when :text then TextField.new(value.to_s)
        when :textarea then TextArea.new(value.to_s, rows: 2)
        when :number then NumberInput.new(value.to_s)
        when :boolean then Checkbox.new("", value: !!value)
        when :select then Select.new(property.options, label: label, value: value)
        when :color then ColorPicker.new(value || "#2563eb", label: "")
        when :date then DatePicker.new(value || Date.today, label: "")
        when :time then TimePicker.new(value || "00:00", label: "")
        end
        control.on_change do |changed, *_args|
          if property.type == :number
            begin
              changed = Float(changed)
            rescue ArgumentError, TypeError
              @errors[key] = ["is not a number"].freeze
              @drafts[key] = changed
              @cx&.window&.request_frame
              next
            end
          end
          @editing_key = key
          set(key, changed)
        ensure
          @editing_key = nil
        end
        control
      end

      def table_action(action)
        return false if @properties.empty?
        @selected_index = case action
        when :previous_option then [@selected_index - 1, 0].max
        when :next_option then [@selected_index + 1, @properties.length - 1].min
        when :first then 0
        when :last then @properties.length - 1
        when :page_up then [@selected_index - visible_count, 0].max
        when :page_down then [@selected_index + visible_count, @properties.length - 1].min
        else return false
        end
        @list.scroll_to(@selected_index, align: :nearest)
        @cx&.window&.request_frame
        true
      end

      def visible_count = [(@height / @row_height).floor, 1].max
    end
  end
end
