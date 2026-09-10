# frozen_string_literal: true

ENV["MT_NO_PLUGINS"] = "1"
gem "minitest", "~> 5.0"
require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zaniah"
