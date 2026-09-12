# frozen_string_literal: true

module Zaniah
  module UI
    class Validation
      def initialize(&rule)
        @rules = []
        @rules << ["is invalid", rule] if rule
      end

      def rule(message = "is invalid", &predicate)
        raise ArgumentError, "validation rule needs a block" unless predicate
        @rules << [message.to_s, predicate]
        self
      end

      def required(message: "is required") = rule(message) { |value| !(value.nil? || value.respond_to?(:empty?) && value.empty?) }
      def format(pattern, message: "has an invalid format") = rule(message) { |value| value.nil? || value.to_s.empty? || pattern.match?(value.to_s) }
      def length(min: nil, max: nil, message: nil)
        raise ArgumentError, "length needs min or max" unless min || max
        rule(message || "has an invalid length") do |value|
          size = value.respond_to?(:length) ? value.length : value.to_s.length
          (!min || size >= min) && (!max || size <= max)
        end
      end
      def number(min: nil, max: nil, message: "is not in range")
        rule(message) do |value|
          number = Float(value)
          (!min || number >= min) && (!max || number <= max)
        rescue ArgumentError, TypeError
          false
        end
      end

      def validate(value)
        @rules.filter_map { |message, predicate| message unless predicate.call(value) }.freeze
      end
    end

    class FormField < Component
      attr_reader :name, :value, :errors

      def initialize(name, value: "", label: nil, control: nil, validation: nil, hint: nil)
        super()
        @name, @value, @label, @control = name.to_sym, value, (label || name.to_s).to_s, control
        @validation = validation || Validation.new
        raise ArgumentError, "validation must respond to validate" unless @validation.respond_to?(:validate)
        @hint, @errors = hint&.to_s, []
      end

      def on_change(&block) = (@on_change = block; self)
      def error_id = "#{@name}-error"

      def validate
        @errors = Array(@validation.validate(@value)).map(&:to_s).freeze
        @errors.empty?
      end

      def build(cx)
        @cx = cx
        control = @control || TextField.new(@value.to_s)
        control.on_change { |value, context| change(value, context) } if control.respond_to?(:on_change)
        root = Div.new.gap(cx.theme.spacing[1]).child(Label.new(@label, size: :sm)).child(control)
        root.child(Label.new(@hint, tone: :muted, size: :xs)) if @hint && @errors.empty?
        root.child(Label.new(@errors.first, tone: :muted, size: :xs).test_id(error_id)) unless @errors.empty?
        @rendered_control = control
        root
      end

      def tui_cells(*) = "#{@label}: #{@value}#{@errors.empty? ? "" : " ! #{@errors.join(", ")}"}"

      def accessibility_node(cx)
        control = @rendered_control&.accessibility_node(cx)
        if control
          control = control.with(states: control.states.merge(invalid: !@errors.empty?, describedby: @errors.empty? ? nil : error_id).freeze)
        end
        node(:group, label: @label, children: [control, *@errors.map { |error| Accessibility.node(role: :alert, label: error, states: {id: error_id}) }].compact)
      end

      private

      def change(value, cx)
        @value = value
        validate unless @errors.empty?
        @on_change&.call(value, self, cx)
        cx&.window&.request_frame
      end
    end

    class Form < Component
      attr_reader :fields

      def initialize(fields = [], submit: "Submit")
        super()
        @fields, @submit_label = [], submit.to_s
        fields.each do |field|
          field.is_a?(FormField) ? @fields << field : self.field(**field)
        end
      end

      def field(name:, **options)
        value = FormField.new(name, **options).on_change { |_value, _field, _cx| @on_change&.call(values) }
        @fields << value
        self
      end

      def on_change(&block) = (@on_change = block; self)
      def on_submit(&block) = (@on_submit = block; self)
      def values = @fields.to_h { |field| [field.name, field.value] }.freeze
      def valid? = @fields.all?(&:validate)

      def build(cx)
        @cx = cx
        Div.new.gap(cx.theme.spacing[3]).children(@fields)
          .child(Button.new(@submit_label).on_click { |event, context| submit(event, context) })
      end

      def submit(event = nil, cx = @cx)
        if valid?
          @on_submit&.call(values, event, cx)
        else
          cx&.window&.request_frame
        end
        self
      end

      def tui_cells(*) = @fields.map(&:tui_cells).push("[#{@submit_label}]").join("\n")
      def accessibility_node(cx) = node(:form, children: @fields.map { |field| field.accessibility_node(cx) } + [Accessibility.node(role: :button, label: @submit_label, actions: [:press])])
    end
  end
end
