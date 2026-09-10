# frozen_string_literal: true

module Zaniah
  class ProcessPool
    Worker = Struct.new(:pid, :reader, :writer, :task, :retire, :thread)
  end
end
