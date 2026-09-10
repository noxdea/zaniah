# frozen_string_literal: true

require "rbs"
require "rbs/test"
require "stringio"
require "pathname"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "zaniah"
require "zaniah/svg"
require "zaniah/platform/tui/text_renderer"

RBS.logger_level = :error
loader = RBS::EnvironmentLoader.new
loader.add(path: Pathname(File.expand_path("../../sig", __dir__)))
environment = RBS::Environment.from_loader(loader).resolve_type_names
tester = RBS::Test::Tester.new(env: environment)
checked = 0
environment.class_decls.each_key do |name|
  next unless name.to_s.start_with?("::Zaniah")
  target = name.to_s.delete_prefix("::").split("::").reduce(Object) do |parent, part|
    break nil unless parent.const_defined?(part, false)
    parent.const_get(part, false)
  end
  next unless target.is_a?(Module)
  tester.builder.build_instance(name).methods.each do |method_name, definition|
    next unless definition.implemented_in == name
    next if method_name == :initialize
    raise "signature without implementation: #{name}##{method_name}" unless target.method_defined?(method_name) || target.private_method_defined?(method_name)
    checked += 1
  end
  tester.builder.build_singleton(name).methods.each do |method_name, definition|
    next unless definition.implemented_in == name
    raise "signature without implementation: #{name}.#{method_name}" unless target.respond_to?(method_name, true)
    checked += 1
  end
  tester.install!(target, sample_size: 10, unchecked_classes: [])
end
raise "type checks did not cover the public API" if checked < 200
ENV["ZANIAH_TYPE_DRIVER"] = "1"
require_relative "smoke"
ENV.delete("ZANIAH_TYPE_DRIVER")
PublicAPISmoke.run
begin
  Zaniah::Point.new("not a coordinate", 0)
  raise "runtime type checker failed to reject an invalid coordinate"
rescue RBS::Test::Tester::TypeError
  # A negative control ensures the hooks really ran.
end
puts "RBS runtime conformance: #{checked} public members checked across #{tester.targets.length} loaded classes/modules"
