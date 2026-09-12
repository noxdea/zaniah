# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "zaniah/data_compat"
require "zaniah/error"
require "zaniah/geometry"
require "zaniah/version"
require "zaniah/accessibility/node"
require "zaniah/accessibility/native_tree"
require "zaniah/accessibility/linux/service"

module Zaniah
  module Accessibility
    def self.perform(*) = false
    def self.focus_at(*) = false
  end
end

dispatcher = Struct.new(:focused).new(nil)
window = Struct.new(:title, :dispatcher).new("AT-SPI smoke", dispatcher)
root = Zaniah::Accessibility.node(role: :button, label: "Save",
  bounds: Zaniah::Bounds.new(0, 0, 100, 30), actions: [:press])
service = Zaniah::Accessibility::Linux::Service.new(window)
service.update(root)
result = nil
query = Thread.new do
  result = Open3.capture3("gdbus", "call", "--address", ENV.fetch("AT_SPI_BUS_ADDRESS"),
    "--timeout", "5", "--dest", service.unique_name,
    "--object-path", "/org/a11y/atspi/accessible/2",
    "--method", "org.a11y.atspi.Accessible.GetRoleName")
end
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
while query.alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  service.poll
  Thread.pass
end
raise "AT-SPI query timed out" if query.alive?
query.join
output, error, status = result
raise "AT-SPI query failed: #{error}" unless status.success?
raise "unexpected AT-SPI role: #{output}" unless output == "('button',)\n"
puts "AT-SPI provider: #{output.strip}"
service.close
