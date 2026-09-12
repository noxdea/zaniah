# frozen_string_literal: true

require "set"

module Zaniah
  class Interactivity
    def initialize = @flags = {}

    def resolve(dispatcher, pointer_position, pointer_down)
      @flags.clear
      chain = dispatcher.hover_chain(pointer_position)
      chain.each { |owner| flags(owner) << :hover }
      chain.each { |owner| flags(owner) << :active } if pointer_down
      owner = dispatcher.focused&.owner
      flags(owner) << :focus if owner
      flags(owner) << :focus_visible if owner && dispatcher.focus_visible?
      self
    end

    def for(owner, static = nil)
      result = @flags[owner]&.dup || Set.new
      result.merge(static) if static
      result
    end

    private

    def flags(owner) = @flags[owner] ||= Set.new
  end
end
