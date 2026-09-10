# frozen_string_literal: true

# Shared packaging gate. Optional argument: a standalone installed-gem smoke.
require "tmpdir"
require "open3"
require "rubygems/package"
require "rbconfig"

root = File.expand_path("..", __dir__)
entry = File.basename(root)
smoke = ARGV.first && File.expand_path(ARGV.fetch(0))
abort "Usage: ruby tools/check_dependencies.rb [smoke.rb]" if ARGV.length > 1 || (smoke && !File.file?(smoke))
specification = Gem::Specification.load(File.join(root, "#{entry}.gemspec"))
dependencies = specification.runtime_dependencies.map(&:name).sort
abort "unexpected runtime gem dependencies" unless dependencies == %w[alhena rexml unicode-display_width]
abort "native extension declaration" unless specification.extensions.empty?
abort "packaged native binary" if specification.files.any? { |path| path.match?(/\.(?:so|bundle|dll|dylib|a|o)\z/i) }
abort "packaged vendor directory" if specification.files.any? { |path| path.start_with?("vendor/") }
%w[LICENSE.txt CHANGELOG.md].each do |path|
  abort "missing packaged #{path}" unless specification.files.include?(path)
end
specification.files.grep(/\.(?:ttf|otf|ttc)\z/i).each do |font|
  directory = File.dirname(font)
  abort "font license not packaged: #{font}" unless specification.files.any? { |path| File.dirname(path) == directory && File.basename(path).match?(/(?:OFL|LICENSE|COPYING)/i) }
end
Dir.mktmpdir("#{entry}-install-") do |directory|
  artifact = File.join(directory, "#{entry}.gem")
  Dir.chdir(root) { Gem::Package.build(specification, false, false, artifact) }
  installation = File.join(directory, "gems")
  gem_command = File.join(RbConfig::CONFIG.fetch("bindir"), "gem")
  environment = {"GEM_HOME" => installation, "GEM_PATH" => ([installation] + Gem.path).join(File::PATH_SEPARATOR), "RUBYLIB" => nil,
    "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil}
  output, status = Open3.capture2e(environment, Gem.ruby, gem_command, "install", "--local", "--ignore-dependencies", "--no-document", "--install-dir", installation, artifact, chdir: directory)
  abort output unless status.success?
  installed = File.join(installation, "gems", "#{entry}-#{specification.version}")
  script = <<~RUBY
    require #{entry.inspect}
    actual = $LOADED_FEATURES.find { |path| path.end_with?(#{"/lib/#{entry}.rb".inspect}) }
    raise "loaded outside clean installation: " + actual.to_s unless actual && File.realpath(actual).start_with?(#{File.realpath(installed).inspect} + File::SEPARATOR)
    load #{smoke.inspect} if #{!smoke.nil?}
    raise "headless/default providers imported Fiddle" if defined?(Fiddle)
    missing = #{dependencies.inspect} - Gem.loaded_specs.keys
    raise "runtime dependencies not loaded: " + missing.join(", ") unless missing.empty?
    source = #{File.join(root, "lib").inspect} + File::SEPARATOR
    leaked = $LOADED_FEATURES.select { |path| path.start_with?(source) }
    raise "workspace library leaked into installed runtime: " + leaked.join(", ") unless leaked.empty?
    puts "isolated install: #{entry} #{specification.version}, runtime dependencies: #{dependencies.join(', ')}, native bridge imports 0"
  RUBY
  output, status = Open3.capture2e(environment, Gem.ruby, "-e", script, chdir: directory)
  abort output unless status.success?
  puts output
end
