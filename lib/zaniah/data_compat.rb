# frozen_string_literal: true

# Ruby 3.2 added Data; Struct provides the same record operations used here.
unless defined?(Data)
  Data = Struct
  def Data.define(*members, &block)
    Struct.new(*members) do
      members.each { |member| undef_method :"#{member}=" }
      define_method(:initialize) do |*values, **keywords|
        if keywords.any?
          raise ArgumentError, "expected either positional or keyword members" unless values.empty? && keywords.keys.sort == members.sort
          values = members.map { |member| keywords.fetch(member) }
        end
        raise ArgumentError, "wrong number of members" unless values.length == members.length
        super(*values)
        freeze
      end
      define_method(:with) do |**changes|
        changes.empty? ? self : self.class.new(**to_h.merge(changes))
      end
      class_eval(&block) if block
    end
  end
end

