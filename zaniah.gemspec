# frozen_string_literal: true

require_relative "lib/zaniah/version"

Gem::Specification.new do |spec|
  spec.name = "zaniah"
  spec.version = Zaniah::VERSION
  spec.authors = ["ydah"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "A pure Ruby UI framework with native and headless rendering"
  spec.homepage = "https://github.com/noxdea/zaniah"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir.chdir(__dir__) { Dir["{lib,sig,exe,assets,docs,examples,tools}/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"].select { |path| File.file?(path) } }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}).map { |path| File.basename(path) }
  spec.require_paths = ["lib"]
  spec.add_dependency "alhena", "~> 0.1.0"
  spec.add_dependency "rexml", "~> 3.4"
  spec.add_dependency "unicode-display_width", "~> 3.2"
end
