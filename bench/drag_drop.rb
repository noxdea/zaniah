# frozen_string_literal: true

require_relative "../lib/zaniah"
require_relative "support/budget"

ids = Array.new(100_000, &:itself)
reads = 0
reorder = Zaniah::DragDrop::Reorder.new(
  locate: ->(*) {},
  keyboard: lambda { |id, direction|
    reads += 1
    index = direction == :previous ? id - 1 : id + 1
    index.between?(0, ids.length - 1) ? Zaniah::DragDrop::Target.new(ids[index], direction == :previous ? :before : :after) : nil
  }
)

Bench.budget("100000-item stable-id keyboard reorder", 20.0, samples: 7) do
  1_000.times { |index| reorder.keyboard(50_000 + (index & 1), index.even? ? :previous : :next) }
end

raise "reorder inspected items outside direct targets" unless reads == 9_000
