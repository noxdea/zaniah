# frozen_string_literal: true

source "https://rubygems.org"
gemspec
gem "wezen", "~> 0.1.0", require: false

group :development, :test do
  gem "benchmark", "~> 0.5"
  gem "fiddle", "~> 1.1"
  gem "prism", "~> 1.0", require: false
  gem "rake", "~> 13.0"
  gem "minitest", "~> 5.0"
  gem "rbs", "~> 4.2", require: false if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3")
end
