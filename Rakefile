# frozen_string_literal: true

require "rake/testtask"
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |test|
  test.libs << "lib" << "test"
  test.pattern = "test/**/*_test.rb"
end

namespace :test do
  Rake::TestTask.new(:golden) do |test|
    test.libs << "lib" << "test"
    test.pattern = "test/golden/**/*_test.rb"
  end
end

desc "Validate RBS signatures"
task :rbs do
  sh "bundle exec rbs -I sig validate"
end

desc "Measure performance (BUDGET=1 enables assertions)"
task :bench do
  Dir["bench/*.rb"].sort.each { |path| ruby "--yjit", path }
end

task default: :test
