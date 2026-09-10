# frozen_string_literal: true

require "benchmark"
require_relative "../lib/zaniah"

database = nil
construction = Benchmark.realtime { database = Zaniah::TextSystem::FontDB.new }
metadata = Benchmark.realtime { database.faces }
font = nil
matching = Benchmark.realtime { font = database.find }
cached = Benchmark.realtime { 1000.times { database.find } } / 1000
puts "font files=#{database.paths.length} faces=#{database.faces.length} selected=#{font.family.inspect}/#{font.index}"
printf "construct=%.3fms metadata=%.3fms match=%.3fms cached=%.6fms\n", construction * 1000, metadata * 1000, matching * 1000, cached * 1000
