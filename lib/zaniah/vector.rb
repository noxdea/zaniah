# frozen_string_literal: true

require_relative "../zaniah" unless defined?(Zaniah::Scene)

module Zaniah
  module Vector
    CONTEXT = %i[transform clip opacity layer sequence].freeze

    Quad = Data.define(:bounds, :fill, :radii, :border, :border_style, *CONTEXT)
    Shadow = Data.define(:bounds, :radii, :color, :blur, :spread, :inset, *CONTEXT)
    Path = Data.define(:outline, :fill, :stroke, :stroke_width, :fill_rule,
      :stroke_cap, :stroke_join, :stroke_miter, *CONTEXT)
    GlyphRun = Data.define(:font, :size, :glyphs, :color, :text, :clusters, *CONTEXT)
    Image = Data.define(:image, :bounds, :source, :pixels, :pixel_width, :pixel_height, :format, *CONTEXT)
    Underline = Data.define(:x, :y, :width, :thickness, :color, :wave, *CONTEXT)
    Raster = Data.define(:bounds, :pixels, :pixel_width, :pixel_height, :format, :color, :source, *CONTEXT)
    Document = Data.define(:width, :height, :commands)

    class Recorder
      attr_reader :width, :height

      def initialize(width: nil, height: nil)
        @width, @height, @commands, @pixels = width, height, [], {}
      end

      def size=(size)
        @width, @height = size.width, size.height
        size
      end

      def clear
        @pixels.clear
        @commands.clear
      end
      def record(command) = @commands << command

      def snapshot_pixels(texture)
        @pixels[[texture.object_id, texture.revision]] ||= texture.data.dup.freeze
      end

      def document
        Document.new(@width, @height, @commands.sort_by { |command| [command.layer, command.sequence] }.freeze)
      end
    end

    def self.record(width:, height:, scale_factor: 1, theme: Theme.light, text_system: nil)
      raise ArgumentError, "block required" unless block_given?
      recorder = Recorder.new(width: width, height: height)
      window = Platform::Headless::Window.new(width: width, height: height, scale_factor: scale_factor)
      window.scene.vector_sink = recorder
      window.app = App.new
      window.app.global(:theme, theme)
      window.text_system = text_system || TextSystem::Renderer.new
      window.render(yield, present: false)
      recorder.document
    ensure
      if window
        window.text_system = nil if text_system
        window.close
      end
    end
  end
end
