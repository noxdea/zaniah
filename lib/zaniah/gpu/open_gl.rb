# frozen_string_literal: true

require_relative "instance_packing"
require_relative "../ffi/library"

module Zaniah
  module GPU
    class OpenGL
      I, P, V, F = Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOID, Fiddle::TYPE_FLOAT
      attr_reader :width, :height, :draw_calls
      VERTEX = <<~GLSL.freeze
        #version 330 core
        layout(location=0) in vec4 rect;
        layout(location=1) in vec4 tint;
        layout(location=2) in vec4 corners;
        layout(location=3) in vec4 border_color;
        layout(location=4) in vec4 extra;
        layout(location=5) in vec4 source;
        uniform vec2 viewport;
        out vec2 local_position; out vec2 size; out vec4 color; out vec4 radii;
        out vec4 border; out vec4 info; out vec2 uv;
        void main() {
          vec2 vertices[4] = vec2[4](vec2(0,0),vec2(1,0),vec2(0,1),vec2(1,1));
          vec2 corner = vertices[gl_VertexID];
          vec2 position = rect.xy + corner * rect.zw;
          if (extra.y == 3) position = gl_VertexID == 0 ? rect.xy : gl_VertexID == 1 ? rect.zw : corners.xy;
          gl_Position = vec4(position.x / viewport.x * 2 - 1, 1 - position.y / viewport.y * 2, 0, 1);
          local_position = corner * rect.zw; size = rect.zw; color = tint;
          radii = corners; border = border_color; info = extra; uv = source.xy + corner * source.zw;
        }
      GLSL
      FRAGMENT = <<~GLSL.freeze
        #version 330 core
        in vec2 local_position; in vec2 size; in vec4 color; in vec4 radii;
        in vec4 border; in vec4 info; in vec2 uv;
        uniform sampler2D atlas;
        out vec4 output_color;
        void main() {
          vec4 result = color;
          if (info.y == 0) {
            float radius = local_position.y < size.y/2 ? (local_position.x < size.x/2 ? radii.x : radii.y) : (local_position.x < size.x/2 ? radii.w : radii.z);
            radius = clamp(radius, 0, min(size.x,size.y)/2);
            vec2 q = abs(local_position - size/2) - size/2 + radius;
            float distance = length(max(q,0)) + min(max(q.x,q.y),0) - radius;
            float coverage = clamp(0.5 - distance, 0, 1);
            if (info.x > 0 && distance >= -info.x) result = border;
            result.a *= coverage;
          } else if (info.y == 1 || info.y == 2) {
            vec4 sample_color = texture(atlas,uv);
            if (info.y == 1) result.a *= sample_color.r; else result *= sample_color;
          }
          output_color = vec4(result.rgb * result.a, result.a);
        }
      GLSL

      def initialize(window, library:, resolver: nil)
        @window, @library, @resolver, @functions, @textures = window, library, resolver, {}, {}
        window.make_current
        version = gl(:glGetString, [I], P, 0x1F02).to_s
        raise Error, "OpenGL 3.3 required (#{version})" if version.to_f < 3.3
        @program = compile_program(VERTEX, FRAGMENT)
        @vao, @buffer = generate(:glGenVertexArrays), generate(:glGenBuffers)
        gl(:glBindVertexArray, [I], V, @vao)
        gl(:glBindBuffer, [I, I], V, 0x8892, @buffer)
        6.times do |location|
          gl(:glEnableVertexAttribArray, [I], V, location)
          gl(:glVertexAttribDivisor, [I, I], V, location, 1)
        end
        gl(:glEnable, [I], V, 0x0BE2)
        gl(:glBlendFunc, [I, I], V, 1, 0x0303)
        @viewport_location = gl(:glGetUniformLocation, [I, P], I, @program, "viewport")
        @white = create_texture(1, 1, data: "\xff".b * 4)
        resize(window.content_size.width, window.content_size.height)
      end
      def gl(name, args, result, *values)
        function = @functions[name] ||= begin
          address = @resolver&.call(name.to_s)
          address = @library.handle[name.to_s] if !address || address.to_i <= 3 || address.to_i == -1
          Fiddle::Function.new(address, args, result, name: name.to_s, need_gvl: false)
        end
        function.call(*values)
      end
      def generate(name)
        bytes = [0].pack("I")
        gl(name, [I, P], V, 1, bytes)
        bytes.unpack1("I")
      end
      def compile_program(vertex, fragment)
        shaders = []
        [[0x8B31, vertex], [0x8B30, fragment]].each do |kind, source|
          shader = gl(:glCreateShader, [I], I, kind)
          pointer = [Fiddle::Pointer[source].to_i].pack("J")
          length = [source.bytesize].pack("i")
          gl(:glShaderSource, [I, I, P, P], V, shader, 1, pointer, length)
          gl(:glCompileShader, [I], V, shader)
          status = [0].pack("i")
          gl(:glGetShaderiv, [I, I, P], V, shader, 0x8B81, status)
          if status.unpack1("i").zero?
            log = "\0" * 8192
            gl(:glGetShaderInfoLog, [I, I, P, P], V, shader, log.bytesize, 0, log)
            gl(:glDeleteShader, [I], V, shader)
            raise Error, "OpenGL shader: #{log.delete("\0") }"
          end
          shaders << shader
        end
        program = gl(:glCreateProgram, [], I)
        shaders.each { |shader| gl(:glAttachShader, [I, I], V, program, shader) }
        gl(:glLinkProgram, [I], V, program)
        status = [0].pack("i")
        gl(:glGetProgramiv, [I, I, P], V, program, 0x8B82, status)
        if status.unpack1("i").zero?
          log = "\0" * 8192
          gl(:glGetProgramInfoLog, [I, I, P, P], V, program, log.bytesize, 0, log)
          gl(:glDeleteProgram, [I], V, program)
          raise Error, "OpenGL program: #{log.delete("\0") }"
        end
        program
      ensure
        shaders&.each { |shader| gl(:glDeleteShader, [I], V, shader) }
      end
      def resize(width, height)
        raise ArgumentError, "invalid viewport" unless width.positive? && height.positive?
        @width, @height, @scale = width.to_i, height.to_i, @window.scale_factor
        @pixel_width, @pixel_height = (width * @scale).round, (height * @scale).round
      end
      def create_texture(width, height, **options) = Texture.new(width, height, **options)
      def create_buffer(size, **options) = Buffer.new(size, **options)
      def create_pipeline(shader:, blend: :premultiplied) = Pipeline.new(shader, blend)
      def begin_frame(clear: "#0000") = FrameEncoder.new(self, clear)

      def render(scene, clear: "#0000", capture: false)
        @window.make_current
        @draw_calls = 0
        gl(:glViewport, [I] * 4, V, 0, 0, @pixel_width, @pixel_height)
        gl(:glDisable, [I], V, 0x0C11)
        gl(:glClearColor, [F] * 4, V, *Color.parse(clear).premultiplied)
        gl(:glClear, [I], V, 0x4000)
        gl(:glEnable, [I], V, 0x0C11)
        gl(:glUseProgram, [I], V, @program)
        gl(:glUniform2f, [I, F, F], V, @viewport_location, @width, @height)
        gl(:glBindVertexArray, [I], V, @vao)
        gl(:glBindBuffer, [I, I], V, 0x8892, @buffer)
        bytes, batches = InstancePacking.pack(scene)
        unless bytes.empty?
          gl(:glBufferData, [I, Fiddle::TYPE_SIZE_T, P, I], V, 0x8892, bytes.bytesize, 0, 0x88E0)
          gl(:glBufferSubData, [I, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_SIZE_T, P], V, 0x8892, 0, bytes.bytesize, bytes)
          batches.each do |(kind, texture, clip), first, count|
            clip = clip ? Bounds.new(0, 0, @width, @height).intersect(clip) : Bounds.new(0, 0, @width, @height)
            next unless clip.width.positive? && clip.height.positive?
            gl(:glScissor, [I] * 4, V, (clip.x * @scale).to_i, ((@height - clip.bottom) * @scale).to_i, (clip.width * @scale).to_i, (clip.height * @scale).to_i)
            6.times do |location|
              gl(:glVertexAttribPointer, [I, I, I, I, I, P], V, location, 4, 0x1406, 0, InstancePacking::STRIDE * 4, (first * InstancePacking::STRIDE + location * 4) * 4)
            end
            native_texture(texture || @white)
            gl(:glDrawArraysInstanced, [I] * 4, V, kind == :triangle ? 4 : 5, 0, kind == :triangle ? 3 : 4, count)
            @draw_calls += 1
          end
        end
        # Capture only when requested; glReadPixels is otherwise an avoidable stall.
        @last_scene, @last_clear = scene, clear
        @captured_pixels = read_pixels if capture
        @window.swap_buffers
      end

      def native_texture(texture)
        entry = @textures[texture]
        unless entry
          entry = @textures[texture] = [generate(:glGenTextures), nil]
          gl(:glBindTexture, [I, I], V, 0x0DE1, entry[0])
          gl(:glTexParameteri, [I] * 3, V, 0x0DE1, 0x2801, 0x2600)
          gl(:glTexParameteri, [I] * 3, V, 0x0DE1, 0x2800, 0x2600)
          gl(:glTexParameteri, [I] * 3, V, 0x0DE1, 0x2802, 0x812F)
          gl(:glTexParameteri, [I] * 3, V, 0x0DE1, 0x2803, 0x812F)
          gl(:glPixelStorei, [I, I], V, 0x0CF5, 1)
          gl(:glTexImage2D, [I] * 8 + [P], V, 0x0DE1, 0, texture.format == :r8 ? 0x8229 : 0x8058, texture.width, texture.height, 0, texture.format == :r8 ? 0x1903 : 0x1908, 0x1401, 0)
        else
          gl(:glBindTexture, [I, I], V, 0x0DE1, entry[0])
        end
        digest = texture.revision
        if entry[1] != digest
          gl(:glTexSubImage2D, [I] * 8 + [P], V, 0x0DE1, 0, 0, 0, texture.width, texture.height, texture.format == :r8 ? 0x1903 : 0x1908, 0x1401, texture.data)
          entry[1] = digest
        end
        entry[0]
      end

      def pixels
        render(@last_scene, clear: @last_clear, capture: true) if @last_scene
        @captured_pixels || "\0".b * (@pixel_width * @pixel_height * 4)
      end
      def read_pixels
        @window.make_current
        gl(:glReadBuffer, [I], V, 0x0405)
        bytes = "\0".b * (@pixel_width * @pixel_height * 4)
        gl(:glReadPixels, [I] * 6 + [P], V, 0, 0, @pixel_width, @pixel_height, 0x1908, 0x1401, bytes)
        rows = @pixel_height.times.map { |y| bytes.byteslice((@pixel_height - y - 1) * @pixel_width * 4, @pixel_width * 4) }.join
        rows.unpack("C*").each_slice(4).flat_map { |r, g, b, a| a.zero? ? [0, 0, 0, 0] : [(r * 255 / a).clamp(0, 255), (g * 255 / a).clamp(0, 255), (b * 255 / a).clamp(0, 255), a] }.pack("C*")
      end
      def write_png(path) = PNG.write(path, @pixel_width, @pixel_height, pixels)
      def release
        @window.make_current
        @textures.each_value { |entry| gl(:glDeleteTextures, [I, P], V, 1, [entry[0]].pack("I")) }
        @textures.clear
        gl(:glDeleteBuffers, [I, P], V, 1, [@buffer].pack("I")) if @buffer
        gl(:glDeleteVertexArrays, [I, P], V, 1, [@vao].pack("I")) if @vao
        gl(:glDeleteProgram, [I], V, @program) if @program
      end
    end
  end
end
