# frozen_string_literal: true

module Zaniah
  module UI
    module Variants
      def variants(definitions = nil, **keywords)
        incoming = (definitions || {}).merge(keywords)
        @variants ||= superclass.respond_to?(:variants) ? superclass.variants.transform_values(&:dup) : {}
        incoming.each { |name, values| (@variants[name] ||= {}).merge!(values) }
        @variants
      end

      def variant_style(theme, selected)
        selected.each_with_object({}) do |(group, choice), style|
          value = variants.fetch(group).fetch(choice) do
            raise ArgumentError, "unknown #{group} variant #{choice.inspect}"
          end
          style.merge!(value.respond_to?(:call) ? value.call(theme) : value)
        end
      end
    end
  end
end
