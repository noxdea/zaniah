# frozen_string_literal: true

require "fileutils"
require "json"

module Bench
  RESULTS = File.expand_path("../results.json", __dir__)
  module_function

  def budget(name, limit_ms, warmup: 2, samples: 11, &block)
    warmup.times(&block)
    timings = samples.times.map do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      block.call
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    end
    median = timings.sort[samples / 2]
    previous = load_results[name]
    change = previous&.positive? ? ((median / previous - 1) * 100).round(1) : nil
    puts JSON.generate(name: name, median_ms: median.round(3), limit_ms: limit_ms, change_percent: change)
    save_result(name, median)
    abort "#{name} exceeds #{limit_ms}ms" if ENV["BUDGET"] == "1" && median > limit_ms
    median
  end

  def load_results
    File.file?(RESULTS) ? JSON.parse(File.read(RESULTS)) : {}
  rescue JSON::ParserError
    {}
  end

  def save_result(name, value)
    results = load_results.merge(name => value)
    FileUtils.mkdir_p(File.dirname(RESULTS))
    File.write(RESULTS, JSON.pretty_generate(results) << "\n")
  end

  private_class_method :load_results, :save_result
end
