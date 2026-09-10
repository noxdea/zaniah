# frozen_string_literal: true

require "fiddle"

module Zaniah
  module FFI
    class Library
      attr_reader :handle
      def initialize(*candidates)
        candidates.each do |candidate|
          begin
            @handle = Fiddle.dlopen(candidate)
            break
          rescue Fiddle::DLError
            next
          end
        end
        raise LoadError, "native library not found: #{candidates.join(', ')}" unless @handle
        @functions = {}
      end

      def fn(name, args, result, need_gvl: true)
        @functions[[name, args, result, need_gvl]] ||= Fiddle::Function.new(
          @handle[name.to_s], args, result, name: name.to_s, need_gvl: need_gvl
        )
      end
    end
  end
end
