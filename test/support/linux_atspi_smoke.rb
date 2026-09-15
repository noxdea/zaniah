# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "zaniah/data_compat"
require "zaniah/error"
require "zaniah/geometry"
require "zaniah/version"
require "zaniah/accessibility/node"
require "zaniah/accessibility/native_tree"
require "zaniah/accessibility/linux/service"

ENV["AT_SPI_BUS_ADDRESS"] ||= ENV.fetch("DBUS_SESSION_BUS_ADDRESS")

module Zaniah
  module Accessibility
    class << self
      attr_accessor :performed
    end
    def self.perform(_window, _node, action, **) = self.performed = action
    def self.focus_at(*) = false
  end
end

def query(service, method, *arguments)
  result = nil
  thread = Thread.new do
    result = Open3.capture3("gdbus", "call", "--address", ENV.fetch("AT_SPI_BUS_ADDRESS"),
      "--timeout", "5", "--dest", service.unique_name,
      "--object-path", "/org/a11y/atspi/accessible/2", "--method", method, *arguments)
  end
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
  while thread.alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    service.poll
    Thread.pass
  end
  raise "AT-SPI query timed out: #{method}" if thread.alive?
  thread.join
  output, error, status = result
  raise "AT-SPI query failed: #{method}: #{error}" unless status.success?
  output
end

dispatcher = Struct.new(:focused).new(nil)
window = Struct.new(:title, :dispatcher).new("AT-SPI smoke", dispatcher)
root = Zaniah::Accessibility.node(role: :button, id: :save, label: "Save",
  bounds: Zaniah::Bounds.new(0, 0, 100, 30), actions: [:press])
service = Zaniah::Accessibility::Linux::Service.new(window)
service.update(root)
role = query(service, "org.a11y.atspi.Accessible.GetRoleName")
name = query(service, "org.freedesktop.DBus.Properties.Get", "org.a11y.atspi.Accessible", "Name")
extents = query(service, "org.a11y.atspi.Component.GetExtents", "0")
action = query(service, "org.a11y.atspi.Action.DoAction", "0")
accessible_id = query(service, "org.freedesktop.DBus.Properties.Get", "org.a11y.atspi.Accessible", "AccessibleId")
raise "unexpected AT-SPI role: #{role}" unless role == "('button',)\n"
raise "unexpected AT-SPI name: #{name}" unless name.include?("Save")
raise "unexpected AT-SPI extents: #{extents}" unless extents == "((0, 0, 100, 30),)\n"
raise "AT-SPI action failed: #{action}" unless action == "(true,)\n" && Zaniah::Accessibility.performed == :press
raise "unexpected stable AT-SPI id: #{accessible_id}" unless accessible_id.include?("save")
puts "AT-SPI provider: role=button, name=Save, extents=0,0,100,30, action=press"
service.close
