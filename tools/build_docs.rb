# frozen_string_literal: true

require "cgi"
require "erb"
require "fileutils"
require "pathname"
require "rdoc"
require "rdoc/markdown"
require "rdoc/markup/to_html"
require "yaml"

ROOT = File.expand_path("../docs", __dir__)
OUTPUT = File.expand_path("../tmp/site/docs", __dir__)
CHECK = ARGV.include?("--check")
PAGES = YAML.safe_load_file(File.join(ROOT, "pages.yml")).fetch("pages")
TEMPLATE = ERB.new(File.read(File.join(ROOT, "_templates", "page.erb")), trim_mode: "-")
GUIDE_LINKS = PAGES.filter_map { |page| [page.fetch("source").sub(/\.md\z/, "_md.html"), page.fetch("path")] if page["kind"] == "markdown" }.to_h

def h(value) = CGI.escapeHTML(value.to_s)
def inline(value) = h(value).gsub(/\`([^\`]+)\`/, '<code>\1</code>')
def link_from(from, to) = Pathname.new(to).relative_path_from(Pathname.new(from).dirname).to_s
def section_id(section) = section.fetch("heading").downcase.gsub(/[^a-z0-9]+/, "-").sub(/-\z/, "")

def markdown_html(page)
  source = File.read(File.join(ROOT, page.fetch("source")), encoding: Encoding::UTF_8)
  source = source.sub(/\A# [^\n]+\n+/, "")
  renderer = if RDoc::Markup::ToHtml.instance_method(:initialize).parameters.first.first == :req
    RDoc::Markup::ToHtml.new(RDoc::Options.new)
  else
    RDoc::Markup::ToHtml.new
  end
  html = renderer.convert(RDoc::Markdown.parse(source))
  html.gsub(/href="([^"]+)"/) do
    href = Regexp.last_match(1)
    target, fragment = href.split("#", 2)
    destination = if GUIDE_LINKS.key?(target)
      link_from(page.fetch("path"), GUIDE_LINKS.fetch(target))
    elsif target.start_with?("adr/") && target.end_with?("_md.html")
      "https://github.com/noxdea/zaniah/blob/main/docs/#{target.sub(/_md\.html\z/, '.md')}"
    elsif target.start_with?("../sig/", "../test/")
      "https://github.com/noxdea/zaniah/blob/main/#{target.delete_prefix('../')}"
    else
      abort "Unmapped guide link: #{page.fetch('source')}: #{href}" if target.end_with?("_md.html")
      target
    end
    "href=\"#{destination}#{"##{fragment}" if fragment}\""
  end
end

def image_dimensions(image)
  header = File.binread(File.join(ROOT, image), 24)
  abort "Invalid preview image: #{image}" unless header.bytesize == 24 && header.start_with?("\x89PNG\r\n\x1a\n".b)
  width, height = header.byteslice(16, 8).unpack("N2")
  scale = image.start_with?("previews/") ? 2 : 1
  abort "Preview must be rendered at 2x: #{image}" unless (width % scale).zero? && (height % scale).zero?
  [width / scale, height / scale]
end

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
PAGES.each_with_index do |page, index|
  path = page.fetch("path")
  previous_page = PAGES[index - 1] if index.positive?
  next_page = PAGES[index + 1]
  rows = reference.select { |row| (row[:names] & page.fetch("components", [])).any? }
  index_groups = page["directory_group"] ? [page.fetch("directory_group")] : groups.keys - ["Getting started", "Guides"]
  guide_html = markdown_html(page) if page["kind"] == "markdown"
  guide_toc = guide_html.scan(/<h2 id="([^"]+)"><a href="#[^"]+">([^<]+)<\/a><\/h2>/) if guide_html
  page.fetch("sections", []).each do |section|
    if section["image"]
      image_path = File.join(ROOT, section.fetch("image"))
      abort "Missing preview: #{image_path}" unless File.file?(image_path)
    end
    RubyVM::InstructionSequence.compile(section["code"]) if section["code"]
  end
  html = TEMPLATE.result(binding).gsub(/[ \t]+$/, "")
  unless CHECK
    output = File.join(OUTPUT, path)
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, html)
  end
end

puts CHECK ? "docs: #{PAGES.length} pages valid" : "docs: wrote #{PAGES.length} pages to #{OUTPUT}"
