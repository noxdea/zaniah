# frozen_string_literal: true

module Zaniah
  module Platform
    module FileDialogOptions
      module_function

      def validate(default_name, directory, filters)
        if default_name && (!default_name.is_a?(String) || default_name.empty? || default_name.match?(/[\\\/\0]/))
          raise ArgumentError, "default name must be a filename"
        end
        if directory && (!directory.is_a?(String) || directory.include?("\0"))
          raise ArgumentError, "directory must be a path"
        end
        raise ArgumentError, "filters must be an array" unless filters.is_a?(Array)
        filters.each do |filter|
          unless filter.is_a?(Hash) && filter[:label].is_a?(String) && !filter[:label].match?(/[\0|]/) &&
              filter[:patterns].is_a?(Array) && !filter[:patterns].empty? &&
              filter[:patterns].all? { |pattern| pattern.is_a?(String) && pattern.match?(/\A(?:\*|\*\.[\w.-]+)\z/) }
            raise ArgumentError, "filters need a label and extension patterns such as *.pcap"
          end
        end
      end
    end
  end
end
