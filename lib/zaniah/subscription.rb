# frozen_string_literal: true

module Zaniah
  class Subscription
    def initialize(&detach) = @detach = detach

    def detach
      callback, @detach = @detach, nil
      callback&.call
    end

    def attached? = !@detach.nil?
  end
end
