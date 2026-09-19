# frozen_string_literal: true

module Zaniah
  module Describe
    Node = Data.define(:type, :props, :children, :key)
    Patch = Data.define(:op, :path, :node, :props)
    MISSING = Object.new.freeze
    private_constant :MISSING

    class Vocabulary
      Definition = Data.define(:props, :children, :factory)

      def self.build(&block)
        raise ArgumentError, "a vocabulary block is required" unless block
        new.tap { |vocabulary| vocabulary.instance_eval(&block) }
      end

      def initialize
        @definitions = {}
      end

      def node(type, props: {}, children: :many, &factory)
        type = Describe.send(:normalize_type, type)
        raise ArgumentError, "node #{type.inspect} is already registered" if @definitions.key?(type)
        raise ArgumentError, "node #{type.inspect} needs a factory" unless factory

        properties = Describe.send(:normalize_props, props)
        properties.each_value { |validator| validate_validator!(validator) }
        validate_children_rule!(children)
        @definitions[type] = Definition.new(properties.freeze, children, factory)
        self
      end

      def allow?(type)
        @definitions.key?(Describe.send(:normalize_type, type))
      rescue ArgumentError
        false
      end

      def validate!(value)
        node = Describe.send(:normalize_node, value)
        validate_node!(node)
      end

      private

      def definition(type)
        @definitions.fetch(type) { raise ArgumentError, "node type #{type.inspect} is not allowed" }
      end

      def validate_node!(node)
        entry = definition(node.type)
        unknown = node.props.keys - entry.props.keys
        raise ArgumentError, "unknown properties for #{node.type.inspect}: #{unknown.join(", ")}" unless unknown.empty?

        props = node.props.each_with_object({}) do |(name, value), validated|
          validator = entry.props.fetch(name)
          value = normalize_property(validator, value)
          raise ArgumentError, "invalid #{name.inspect} property for #{node.type.inspect}" unless valid_property?(validator, value)
          validated[name] = value
        end
        children = node.children.map { |child| validate_node!(child) }.freeze
        validated = Node.new(node.type, props.freeze, children, node.key)
        validate_children!(entry.children, validated)
        duplicate_keys = children.map(&:key).reject(&:nil?).tally.select { |_key, count| count > 1 }.keys
        raise ArgumentError, "duplicate child keys for #{node.type.inspect}: #{duplicate_keys.inspect}" unless duplicate_keys.empty?
        validated
      end

      def validate_children!(rule, node)
        count = node.children.length
        valid = case rule
        when :none then count.zero?
        when :one then count == 1
        when :many then true
        when Integer then count == rule
        when Range then rule.cover?(count)
        end
        raise ArgumentError, "invalid child count for #{node.type.inspect}" unless valid
      end

      def validate_children_rule!(rule)
        return if %i[none one many].include?(rule) || rule.is_a?(Integer) || rule.is_a?(Range)
        raise ArgumentError, "children must be :none, :one, :many, an Integer, or a Range"
      end

      def validate_validator!(validator)
        valid = validator.is_a?(Array) || validator.is_a?(Module) || validator.respond_to?(:call) ||
          %i[any string integer number boolean array hash symbol handler].include?(validator)
        raise ArgumentError, "unsupported property validator #{validator.inspect}" unless valid
      end

      def valid_property?(validator, value)
        case validator
        when :any then true
        when :string then value.is_a?(String)
        when :integer then value.is_a?(Integer)
        when :number then value.is_a?(Numeric)
        when :boolean then value == true || value == false
        when :array then value.is_a?(Array)
        when :hash then value.is_a?(Hash)
        when :symbol then value.is_a?(Symbol)
        when :handler then value.is_a?(String) || value.is_a?(Array)
        when Array then validator.include?(value)
        when Module then value.is_a?(validator)
        else validator.call(value)
        end
      end

      def normalize_property(validator, value)
        return value.to_sym if validator == :symbol && value.is_a?(String)
        if validator.is_a?(Array) && value.is_a?(String) && validator.any? { |item| item.is_a?(Symbol) }
          symbol = value.to_sym
          return symbol if validator.include?(symbol)
        end
        value
      end

      def build_node(node, children, on_event)
        entry = definition(node.type)
        props = node.props.each_with_object({}) do |(name, value), converted|
          converted[name] = entry.props[name] == :handler ? event_handler(value, on_event) : value
        end
        element = entry.factory.call(props.freeze, children.freeze)
        unless element.respond_to?(:request_layout) && element.respond_to?(:prepaint) && element.respond_to?(:paint)
          raise TypeError, "factory for #{node.type.inspect} must return a renderable element"
        end
        element.key(node.key) if !node.key.nil? && element.respond_to?(:key)
        element
      end

      def event_handler(id, on_event)
        ->(payload = nil, *) { on_event.call(id, payload) }
      end
      private_constant :Definition
    end

    Mounted = Struct.new(:node, :element, :children)
    private_constant :Mounted

    class Surface
      def initialize(vocabulary:, on_event:)
        raise ArgumentError, "vocabulary must be a Vocabulary" unless vocabulary.is_a?(Vocabulary)
        raise ArgumentError, "on_event must be callable" unless on_event.respond_to?(:call)
        @vocabulary, @on_event = vocabulary, on_event
      end

      def replace(value)
        if value.nil?
          @node = @mounted = @element = nil
        else
          node = @vocabulary.validate!(value)
          mounted = Describe.send(:mount, node, @vocabulary, @on_event, nil)
          @node, @mounted, @element = node, mounted, mounted.element
        end
        self
      end

      def apply(values)
        patches = Array(values).map { |value| Describe.send(:normalize_patch, value) }
        candidate = patches.reduce(@node) { |node, patch| Describe.send(:apply_patch, node, patch) }
        candidate = @vocabulary.validate!(candidate) if candidate
        mounted = candidate && Describe.send(:mount, candidate, @vocabulary, @on_event, @mounted)
        @node, @mounted, @element = candidate, mounted, mounted&.element
        self
      end

      def element = @element
      def empty? = @element.nil?
    end

    class << self
      def build(value, vocabulary:, on_event:)
        raise ArgumentError, "vocabulary must be a Vocabulary" unless vocabulary.is_a?(Vocabulary)
        raise ArgumentError, "on_event must be callable" unless on_event.respond_to?(:call)
        node = vocabulary.validate!(value)
        mount(node, vocabulary, on_event, nil).element
      end

      def diff(previous, current)
        previous = normalize_node(previous) if previous
        current = normalize_node(current) if current
        return [] if previous == current
        return [Patch.new(:insert, [].freeze, current, nil)] unless previous
        return [Patch.new(:remove, [].freeze, nil, nil)] unless current

        [].tap { |patches| diff_node(previous, current, [], patches) }
      end

      private

      def normalize_type(type)
        raise ArgumentError, "node type must be a Symbol or String" unless type.is_a?(Symbol) || type.is_a?(String)
        type.to_sym
      end

      def normalize_props(value)
        raise ArgumentError, "props must be a Hash" unless value.is_a?(Hash)
        value.each_with_object({}) do |(key, item), props|
          raise ArgumentError, "property names must be Symbols or Strings" unless key.is_a?(Symbol) || key.is_a?(String)
          name = key.to_sym
          raise ArgumentError, "duplicate property #{name.inspect}" if props.key?(name)
          props[name] = item
        end
      end

      def normalize_node(value)
        return Node.new(value.type, normalize_props(value.props).freeze,
          normalize_children(value.children), value.key) if value.is_a?(Node)
        raise ArgumentError, "node must be a Describe::Node or Hash" unless value.is_a?(Hash)

        keys = value.keys.map { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
        unknown = keys - %i[type props children key]
        raise ArgumentError, "unknown node fields: #{unknown.inspect}" unless unknown.empty?
        type = fetch_field(value, :type)
        props = fetch_field(value, :props, {})
        children = fetch_field(value, :children, [])
        key = fetch_field(value, :key, nil)
        Node.new(normalize_type(type), normalize_props(props).freeze, normalize_children(children), key)
      end

      def normalize_children(value)
        raise ArgumentError, "children must be an Array" unless value.is_a?(Array)
        value.map { |child| normalize_node(child) }.freeze
      end

      def fetch_field(hash, name, default = MISSING)
        return hash[name] if hash.key?(name)
        string = name.to_s
        return hash[string] if hash.key?(string)
        raise ArgumentError, "node is missing #{name.inspect}" if default.equal?(MISSING)
        default
      end

      def mount(node, vocabulary, on_event, previous)
        return previous if previous&.node == node

        previous_children = previous&.children || []
        keyed = previous_children.each_with_object({}) do |mounted, by_key|
          key = mounted.node.key
          by_key[[mounted.node.type, key]] = mounted unless key.nil?
        end
        children = node.children.each_with_index.map do |child, index|
          match = if child.key.nil?
            previous_children[index] if previous_children[index]&.node&.key.nil?
          else
            keyed[[child.type, child.key]]
          end
          mount(child, vocabulary, on_event, match)
        end
        element = vocabulary.send(:build_node, node, children.map(&:element), on_event)
        Mounted.new(node, element, children)
      end

      def diff_node(previous, current, path, patches)
        unless previous.type == current.type && previous.key == current.key
          patches << Patch.new(:replace, path.freeze, current, nil)
          return
        end
        patches << Patch.new(:update, path.freeze, nil, current.props) unless previous.props == current.props
        diff_children(previous.children, current.children, path, patches)
      end

      def diff_children(previous, current, path, patches)
        working = previous.dup
        index = 0
        while index < current.length
          wanted = current[index]
          present = working[index]
          if present && same_slot?(present, wanted)
            diff_node(present, wanted, path + [index], patches)
            working[index] = wanted
            index += 1
          elsif present&.key && !current[index..].any? { |node| same_slot?(present, node) }
            patches << Patch.new(:remove, (path + [index]).freeze, nil, nil)
            working.delete_at(index)
          elsif wanted.key && (from = working.each_index.find { |at| at > index && same_slot?(working[at], wanted) })
            patches << Patch.new(:remove, (path + [from]).freeze, nil, nil)
            working.delete_at(from)
            patches << Patch.new(:insert, (path + [index]).freeze, wanted, nil)
            working.insert(index, wanted)
            index += 1
          elsif wanted.key || present.nil?
            patches << Patch.new(:insert, (path + [index]).freeze, wanted, nil)
            working.insert(index, wanted)
            index += 1
          else
            diff_node(present, wanted, path + [index], patches)
            working[index] = wanted
            index += 1
          end
        end
        (working.length - 1).downto(current.length) do |at|
          patches << Patch.new(:remove, (path + [at]).freeze, nil, nil)
        end
      end

      def same_slot?(left, right)
        if !left.key.nil? || !right.key.nil?
          !left.key.nil? && left.key == right.key
        else
          left.type == right.type
        end
      end

      def normalize_patch(value)
        return Patch.new(normalize_operation(value.op), normalize_path(value.path),
          value.node && normalize_node(value.node), value.props && normalize_props(value.props).freeze) if value.is_a?(Patch)
        raise ArgumentError, "patch must be a Describe::Patch or Hash" unless value.is_a?(Hash)
        op = normalize_operation(fetch_patch_field(value, :op))
        path = normalize_path(fetch_patch_field(value, :path))
        node = fetch_patch_field(value, :node, nil)
        props = fetch_patch_field(value, :props, nil)
        Patch.new(op, path, node && normalize_node(node), props && normalize_props(props).freeze)
      end

      def fetch_patch_field(hash, name, default = MISSING)
        return hash[name] if hash.key?(name)
        return hash[name.to_s] if hash.key?(name.to_s)
        raise ArgumentError, "patch is missing #{name.inspect}" if default.equal?(MISSING)
        default
      end

      def normalize_operation(value)
        raise ArgumentError, "patch operation must be a Symbol or String" unless value.is_a?(Symbol) || value.is_a?(String)
        value.to_sym
      end

      def normalize_path(value)
        raise ArgumentError, "patch path must be an Array" unless value.is_a?(Array)
        value.map do |index|
          index = Integer(index)
          raise ArgumentError, "patch path indexes must be non-negative" if index.negative?
          index
        end.freeze
      end

      def apply_patch(root, patch)
        raise ArgumentError, "unknown patch operation #{patch.op.inspect}" unless %i[replace insert remove update].include?(patch.op)
        case patch.op
        when :replace
          raise ArgumentError, "replace patch needs a node" unless patch.node
          return patch.node if patch.path.empty?
          rewrite_at(root, patch.path) { |_node| patch.node }
        when :insert
          raise ArgumentError, "insert patch needs a node" unless patch.node
          return patch.node if patch.path.empty? && root.nil?
          change_children(root, patch.path, insert: patch.node)
        when :remove
          return nil if patch.path.empty?
          change_children(root, patch.path, remove: true)
        when :update
          raise ArgumentError, "update patch needs props" unless patch.props
          rewrite_at(root, patch.path) { |node| node.with(props: patch.props) }
        end
      end

      def rewrite_at(node, path, &block)
        raise ArgumentError, "patch path does not exist" unless node
        return yield(node) if path.empty?
        index = path.first
        raise ArgumentError, "patch path does not exist" unless index < node.children.length
        children = node.children.dup
        children[index] = rewrite_at(children[index], path.drop(1), &block)
        node.with(children: children.freeze)
      end

      def change_children(root, path, insert: nil, remove: false)
        raise ArgumentError, "insert and remove require a child path" if path.empty?
        index = path.last
        rewrite_at(root, path[0...-1]) do |parent|
          children = parent.children.dup
          if remove
            raise ArgumentError, "patch path does not exist" unless index < children.length
            children.delete_at(index)
          else
            raise ArgumentError, "patch insertion is outside the children" unless index <= children.length
            children.insert(index, insert)
          end
          parent.with(children: children.freeze)
        end
      end
    end
  end
end
