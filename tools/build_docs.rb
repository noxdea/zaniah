# frozen_string_literal: true

require "cgi"
require "erb"
require "fileutils"
require "pathname"
require "yaml"

ROOT = File.expand_path("../docs", __dir__)
PAGES = YAML.safe_load_file(File.join(ROOT, "pages.yml")).fetch("pages")
TEMPLATE = ERB.new(File.read(File.join(ROOT, "_templates", "page.erb")), trim_mode: "-")

def h(value) = CGI.escapeHTML(value.to_s)
def inline(value) = h(value).gsub(/\`([^\`]+)\`/, '<code>\1</code>')
def link_from(from, to) = Pathname.new(to).relative_path_from(Pathname.new(from).dirname).to_s
def section_id(section) = section.fetch("heading").downcase.gsub(/[^a-z0-9]+/, "-").sub(/-\z/, "")

reference = File.readlines(File.join(ROOT, "components.md")).filter_map do |line|
  next unless line.start_with?("| L")
  columns = line.split("|").map(&:strip)
  names = columns.fetch(2).scan(/\`([^\`]+)\`/).flatten
  {names: names, constructor: columns.fetch(3), variants: columns.fetch(4), role: columns.fetch(5)}
end

component_pages = PAGES.select { |page| page["kind"] == "component" }
reference_names = reference.flat_map { |row| row[:names] }
assigned_names = component_pages.flat_map { |page| page.fetch("components") }
missing = reference_names - assigned_names
unknown = assigned_names - reference_names
duplicate = assigned_names.tally.select { |_name, count| count > 1 }.keys
abort "Invalid component map: missing=#{missing.inspect}, unknown=#{unknown.inspect}, duplicate=#{duplicate.inspect}" unless (missing + unknown + duplicate).empty?

paths = PAGES.map { |page| page.fetch("path") }
abort "Duplicate documentation paths" unless paths.uniq.length == paths.length

groups = PAGES.group_by { |page| page.fetch("group") }
changes = []
PAGES.each_with_index do |page, index|
  path = page.fetch("path")
  previous_page = PAGES[index - 1] if index.positive?
  next_page = PAGES[index + 1]
  rows = reference.select { |row| (row[:names] & page.fetch("components", [])).any? }
  page.fetch("sections", []).each do |section|
    if section["image"]
      image_path = File.join(ROOT, section.fetch("image"))
      abort "Missing preview: #{image_path}" unless File.file?(image_path)
    end
    RubyVM::InstructionSequence.compile(section["code"]) if section["code"]
  end
  html = TEMPLATE.result(binding).gsub(/[ \t]+$/, "")
  output = File.join(ROOT, path)
  if ARGV.include?("--check")
    changes << path unless File.file?(output) && File.read(output, encoding: Encoding::UTF_8) == html
  else
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, html)
  end
end

abort "Regenerate documentation: #{changes.join(', ')}" unless changes.empty?
puts ARGV.include?("--check") ? "docs: #{PAGES.length} pages up to date" : "docs: wrote #{PAGES.length} pages"
