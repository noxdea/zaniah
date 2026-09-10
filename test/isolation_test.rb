# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class IsolationTest < Minitest::Test
  def test_built_gem_runs_with_declared_dependencies
    root = File.expand_path("..", __dir__)
    refute Dir[File.join(root, "lib/**/*.rb")].any? { |path| File.read(path).match?(/\bCanopus\b/) }, "UI must not reference its editor consumer"
    output, status = Open3.capture2e(RbConfig.ruby, File.join(root, "tools/check_dependencies.rb"),
      File.join(__dir__, "type/smoke.rb"), chdir: root)
    assert status.success?, output
    assert_equal 1, output.scan("public API smoke:").length
    assert_includes output, "runtime dependencies: alhena, rexml, unicode-display_width"
  end
end
