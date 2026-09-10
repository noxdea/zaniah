# frozen_string_literal: true

require "fiddle"
require "benchmark"

library = Fiddle.dlopen(RUBY_PLATFORM.match?(/mingw|mswin/) ? "msvcrt.dll" : nil)
count = Integer(ENV.fetch("N", "1000000"))
text = "a" * 16
pointer = Fiddle::Pointer[text]
[true, false].each do |gvl|
  function = Fiddle::Function.new(library["strlen"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_SIZE_T, need_gvl: gvl)
  [text, pointer].each do |value|
    elapsed = Benchmark.realtime { count.times { function.call(value) } }
    puts "strlen gvl=#{gvl} #{value.class}: #{(elapsed * 1e6 / count).round(3)}us/call"
  end
end
