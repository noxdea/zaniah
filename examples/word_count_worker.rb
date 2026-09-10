# frozen_string_literal: true

# Standalone, fixed entrypoint loaded by ProcessPool in each spawned Ruby.
module WordCountWorker
  def self.call(data)
    {"words" => data.fetch("text").split.length, "pid" => Process.pid}
  end
end
