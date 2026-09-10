# frozen_string_literal: true

require "rake/testtask"
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |test|
  test.libs << "lib" << "test"
  test.pattern = "test/**/*_test.rb"
end

desc "Measure performance (BUDGET=1 enables assertions)"
task :bench do
  Dir["bench/*.rb"].sort.each { |path| ruby "--yjit", path }
end

task default: :test
