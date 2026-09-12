# frozen_string_literal: true

require "fileutils"
require "alhena"

module Zaniah
  class UITest < Minitest::Test
    include InteractionHelper

    FIXTURES = File.expand_path("../golden/fixtures", __dir__)
    DIFFS = File.expand_path("../golden/diff", __dir__)

    def setup
      super
      @clock = TestClock.new
      @app = App.new(clock: @clock)
      @window = @app.open_window(width: 800, height: 600, scale_factor: 1)
      font = Alhena::Font.open(File.expand_path("../../assets/fonts/Abel-Regular.ttf", __dir__))
      @window.text_system = TextSystem::Renderer.new(font: font, font_db: TextSystem::FontDB.new(paths: []))
    end

    def teardown
      @window&.close
      @app&.executor&.shutdown
      super
    end

    def assert_golden(name, pointer: nil, focus: nil, theme: :dark, tolerance: 2, &block)
      skip "golden images run in the dedicated CI job" if ENV["GOLDEN"] == "skip"
      raise ArgumentError, "invalid golden name" unless name.match?(/\A[\w-]+(?:\/[\w-]+)*\z/)

      @app.global(:theme, theme.is_a?(Theme) ? theme : Theme.public_send(theme))
      element = block.call
      @window.draw { element }
      move_to(*pointer) if pointer
      @window.dispatcher.focus(focus) if focus
      frame!
      actual = PNG.encode(@window.device.width, @window.device.height, @window.device.pixels)
      fixture = File.join(FIXTURES, "#{name}.png")
      if ENV["GOLDEN"] == "update"
        FileUtils.mkdir_p(File.dirname(fixture))
        File.binwrite(fixture, actual)
        return assert File.file?(fixture)
      end

      assert File.file?(fixture), "missing golden image #{fixture}; run GOLDEN=update bundle exec rake test:golden"
      expected = File.binread(fixture)
      compare_golden(name, expected, actual, tolerance)
    end

    private

    def compare_golden(name, expected_png, actual_png, tolerance)
      expected_width, expected_height, expected = PNG.decode(expected_png)
      actual_width, actual_height, actual = PNG.decode(actual_png)
      assert_equal [expected_width, expected_height], [actual_width, actual_height]
      changed = 0
      diff = "\0".b * expected.bytesize
      expected.bytes.each_index do |index|
        delta = (expected.getbyte(index) - actual.getbyte(index)).abs
        changed += 1 if index % 4 == 0 && 4.times.any? { |channel| (expected.getbyte(index + channel) - actual.getbyte(index + channel)).abs > tolerance }
        diff.setbyte(index, index % 4 == 3 ? 255 : delta.zero? ? 0 : 255)
      end
      return assert true if changed.to_f / (expected_width * expected_height) < 0.001

      write_diff(name, expected_png, actual_png, expected_width, expected_height, diff)
      flunk "golden image #{name} differs at #{changed} pixels"
    end

    def write_diff(name, expected, actual, width, height, diff)
      directory = File.join(DIFFS, File.dirname(name))
      FileUtils.mkdir_p(directory)
      basename = File.basename(name)
      File.binwrite(File.join(directory, "#{basename}.expected.png"), expected)
      File.binwrite(File.join(directory, "#{basename}.actual.png"), actual)
      File.binwrite(File.join(directory, "#{basename}.diff.png"), PNG.encode(width, height, diff))
    end
  end
end
