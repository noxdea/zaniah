# frozen_string_literal: true

module Zaniah
  module Platform
    module Mac
      def self.displays
        list = O.send(O.klass("NSScreen"), "screens")
        count = O.send(list, "count", result: :ulong)
        return [] if count.zero?
        first = O.send(list, "objectAtIndex:", 0, args: [:ulong])
        primary_height = O.send(first, "frame", result: :rect)[3]
        Array.new(count) do |index|
          screen = O.send(list, "objectAtIndex:", index, args: [:ulong])
          x, y, width, height = O.send(screen, "frame", result: :rect)
          description = O.send(screen, "deviceDescription")
          identifier = O.send(description, "objectForKey:", O.string("NSScreenNumber"), args: [:pointer])
          Display.new(O.send(identifier, "unsignedIntValue", result: :uint), O.text(O.send(screen, "localizedName")),
            Bounds.new(x, primary_height - y - height, width, height), O.send(screen, "backingScaleFactor", result: :double), index.zero?)
        end
      end
    end
  end
end
