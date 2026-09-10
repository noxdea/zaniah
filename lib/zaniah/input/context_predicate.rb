# frozen_string_literal: true

require "json"
require "strscan"

module Zaniah
  module Input
    # Parse a deliberately small predicate grammar. Settings never become Ruby code.
    class ContextPredicate
      def initialize(source)
        @tokens = []
        scanner = StringScanner.new(source.to_s)
        until scanner.eos?
          next if scanner.scan(/\s+/)
          token = scanner.scan(/&&|\|\||==|!=|[!()]|[\w.:-]+|"(?:\\.|[^"\\])*"/)
          raise ArgumentError, "invalid context expression at #{scanner.pos}" unless token
          @tokens << token
        end
        @position = 0
        @tree = @tokens.empty? ? [:literal, true] : expression
        raise ArgumentError, "unexpected context token" unless @position == @tokens.length
      end

      def call(context) = !!evaluate(@tree, context)

      private

      def peek = @tokens[@position]
      def take = @tokens[@position].tap { @position += 1 }

      def expression
        left = conjunction
        while peek == "||"
          take
          left = [:or, left, conjunction]
        end
        left
      end

      def conjunction
        left = atom
        while peek == "&&"
          take
          left = [:and, left, atom]
        end
        left
      end

      def atom
        if peek == "!"
          take
          return [:not, atom]
        end
        if peek == "("
          take
          node = expression
          raise ArgumentError, "unclosed context group" unless take == ")"
          return node
        end
        name = take
        raise ArgumentError, "context identifier expected" unless name && name.match?(/\A[\w.:-]+\z/)
        if ["==", "!="].include?(peek)
          operator, operand = take, take
          raise ArgumentError, "context value expected" unless operand && operand.match?(/\A(?:[\w.:-]+|".*")\z/)
          value = operand.start_with?('"') ? JSON.parse(operand) : operand
          [operator.to_sym, name, value]
        else
          [:id, name]
        end
      end

      def evaluate(node, context)
        kind, a, b = node
        lookup = ->(name) { context.key?(name) ? context[name] : context[name.to_sym] }
        case kind
        when :literal then a
        when :id then a == "true" || (a != "false" && lookup.call(a))
        when :and then evaluate(a, context) && evaluate(b, context)
        when :or then evaluate(a, context) || evaluate(b, context)
        when :not then !evaluate(a, context)
        when :== then lookup.call(a).to_s == b
        when :!= then lookup.call(a).to_s != b
        end
      end
    end
  end
end
