# frozen_string_literal: true

require_relative "instance_packing"
require_relative "../ffi/objc"

module Zaniah
  module GPU
    class Metal
      O = FFI::ObjC
      LIB = FFI::Library.new("/System/Library/Frameworks/Metal.framework/Metal")
      POINTER_ARGS = [:pointer].freeze
      ULONG_ARGS = [:ulong].freeze
      BUFFER_ARGS = [:pointer, :ulong, :ulong].freeze
      TEXTURE_ARGS = [:pointer, :ulong].freeze
      DRAW_ARGS = [:ulong, :ulong, :ulong, :ulong].freeze
      CLEAR_ARGS = [:clear_color].freeze
      attr_reader :width, :height, :draw_calls
      SOURCE = <<~MSL.freeze
        #include <metal_stdlib>
        using namespace metal;
        struct Vertex { float4 position [[position]]; float2 local; float2 size;
          float4 color; float4 secondary; float4 radii; float4 border; float4 widths;
          float4 gradient; float4 center_kind; float2 uv; float dash; };
        vertex Vertex zaniah_vertex(uint v [[vertex_id]], uint instance [[instance_id]],
            const device float *data [[buffer(0)]], constant float2 &viewport [[buffer(1)]]) {
          const device float *p = data + instance * 40;
          float2 corners[4] = {float2(0,0),float2(1,0),float2(0,1),float2(1,1)};
          float2 corner = corners[v], size = float2(p[2],p[3]);
          float2 position = float2(p[0],p[1]) + corner * size;
          if (p[31] == 3) position = v == 0 ? float2(p[0],p[1]) : v == 1 ? float2(p[2],p[3]) : float2(p[12],p[13]);
          position = float2(p[32] * position.x + p[34] * position.y + p[36],
                            p[33] * position.x + p[35] * position.y + p[37]);
          Vertex out;
          out.position = float4(position.x / viewport.x * 2 - 1, 1 - position.y / viewport.y * 2, 0, 1);
          out.local = corner * size; out.size = size;
          out.color = float4(p[4],p[5],p[6],p[7]); out.secondary = float4(p[8],p[9],p[10],p[11]);
          out.radii = float4(p[12],p[13],p[14],p[15]); out.border = float4(p[16],p[17],p[18],p[19]);
          out.widths = float4(p[20],p[21],p[22],p[23]); out.gradient = float4(p[24],p[25],p[26],p[27]);
          out.center_kind = float4(p[28],p[29],p[30],p[31]);
          out.uv = float2(p[20],p[21]) + corner * float2(p[22],p[23]); out.dash = p[39]; return out;
        }
        fragment float4 zaniah_fragment(Vertex in [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
          float4 color = in.color;
          if (in.center_kind.w == 0) {
            if (in.gradient.x > 0) {
              float2 normalized = in.local / in.size;
              float raw = in.gradient.x == 1
                ? dot(normalized - 0.5f, float2(cos(in.gradient.w * 0.01745329252f), sin(in.gradient.w * 0.01745329252f))) + 0.5f
                : length(normalized - in.center_kind.xy) / in.center_kind.z;
              color = mix(in.color, in.secondary, clamp((raw - in.gradient.y) / max(in.gradient.z - in.gradient.y, 0.000001f), 0.0f, 1.0f));
            }
            float radius = in.local.y < in.size.y/2 ? (in.local.x < in.size.x/2 ? in.radii.x : in.radii.y) : (in.local.x < in.size.x/2 ? in.radii.w : in.radii.z);
            radius = clamp(radius, 0.0f, min(in.size.x,in.size.y)/2);
            float2 q = abs(in.local - in.size/2) - in.size/2 + radius;
            float distance = length(max(q,0.0f)) + min(max(q.x,q.y),0.0f) - radius;
            float coverage = clamp(0.5f - distance, 0.0f, 1.0f);
            float4 edge_distance = float4(in.local.y, in.size.x-in.local.x, in.size.y-in.local.y, in.local.x);
            float edge = min(min(edge_distance.x,edge_distance.y),min(edge_distance.z,edge_distance.w));
            float border_width = edge == edge_distance.x ? in.widths.x : edge == edge_distance.y ? in.widths.y : edge == edge_distance.z ? in.widths.z : in.widths.w;
            float coordinate = edge == edge_distance.x || edge == edge_distance.z ? in.local.x : in.local.y;
            if (border_width > 0 && distance >= -border_width && !(in.dash == 1 && fmod(coordinate,6.0f) >= 3.0f)) color = in.border;
            color.a *= coverage;
          } else if (in.center_kind.w == 1 || in.center_kind.w == 2) {
            constexpr sampler texture_sampler(coord::normalized, address::clamp_to_edge, filter::nearest);
            float4 sample = atlas.sample(texture_sampler,in.uv);
            if (in.center_kind.w == 1) color.a *= sample.r; else color *= sample;
          }
          return float4(color.rgb * color.a, color.a);
        }
      MSL

      def initialize(window)
        @window, @textures = window, {}
        @device = LIB.fn(:MTLCreateSystemDefaultDevice, [], Fiddle::TYPE_VOIDP).call.to_i
        raise Error, "Metal device unavailable" if @device.zero?
        @queue = O.send(@device, "newCommandQueue")
        O.send(window.layer, "setDevice:", @device, args: [:pointer], result: :void)
        O.send(window.layer, "setPixelFormat:", 80, args: [:ulong], result: :void)
        O.send(window.layer, "setFramebufferOnly:", 0, args: [:bool], result: :void)
        @pipeline = compile_pipeline(SOURCE)
        # Metal render-pass descriptors are reusable; only the drawable target
        # and a changed clear color need updating between encoders.
        @render_pass = O.new("MTLRenderPassDescriptor")
        @color_attachment = O.send(O.send(@render_pass, "colorAttachments"), "objectAtIndexedSubscript:", 0, args: ULONG_ARGS)
        O.send(@color_attachment, "setLoadAction:", 2, args: ULONG_ARGS, result: :void)
        O.send(@color_attachment, "setStoreAction:", 1, args: ULONG_ARGS, result: :void)
        @clear_input = Object.new
        @scissor = Array.new(4, 0)
        @scissor_signature = FFI::Struct::Signature.new([:pointer, :pointer, :scissor], :void)
        @scissor_selector = O.selector("setScissorRect:")
        @white = create_texture(1, 1, data: "\xff".b * 4)
        resize(window.content_size.width, window.content_size.height)
      end

      def compile_pipeline(source)
        error = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        error[0, Fiddle::SIZEOF_VOIDP] = [0].pack("J")
        library = O.send(@device, "newLibraryWithSource:options:error:", O.string(source), 0, error,
                         args: [:pointer] * 3)
        raise Error, native_error(error, "Metal shader compilation failed") if library.zero?
        vertex = O.send(library, "newFunctionWithName:", O.string("zaniah_vertex"), args: [:pointer])
        fragment = O.send(library, "newFunctionWithName:", O.string("zaniah_fragment"), args: [:pointer])
        descriptor = O.new("MTLRenderPipelineDescriptor")
        O.send(descriptor, "setVertexFunction:", vertex, args: [:pointer], result: :void)
        O.send(descriptor, "setFragmentFunction:", fragment, args: [:pointer], result: :void)
        attachment = O.send(O.send(descriptor, "colorAttachments"), "objectAtIndexedSubscript:", 0, args: [:ulong])
        O.send(attachment, "setPixelFormat:", 80, args: [:ulong], result: :void)
        O.send(attachment, "setBlendingEnabled:", 1, args: [:bool], result: :void)
        {"setSourceRGBBlendFactor:" => 1, "setSourceAlphaBlendFactor:" => 1,
         "setDestinationRGBBlendFactor:" => 5, "setDestinationAlphaBlendFactor:" => 5}.each do |name, value|
          O.send(attachment, name, value, args: [:ulong], result: :void)
        end
        pipeline = O.send(@device, "newRenderPipelineStateWithDescriptor:error:", descriptor, error, args: [:pointer, :pointer])
        raise Error, native_error(error, "Metal pipeline creation failed") if pipeline.zero?
        pipeline
      ensure
        [descriptor, vertex, fragment, library].compact.each { |object| O.release(object) }
      end

      def resize(width, height)
        raise ArgumentError, "invalid viewport" unless width.positive? && height.positive?
        @width, @height = width.to_i, height.to_i
        @scale = @window.scale_factor
        @pixel_width, @pixel_height = (width * @scale).round, (height * @scale).round
        @viewport_bytes = [@width, @height].pack("f2")
        @viewport_pointer = Fiddle::Pointer[@viewport_bytes]
        @full_scissor = [0, 0, @pixel_width, @pixel_height].freeze
        O.send(@window.layer, "setContentsScale:", @scale, args: [:double], result: :void)
        O.send(@window.layer, "setDrawableSize:", [@pixel_width, @pixel_height], args: [:size], result: :void)
      end
      def create_texture(width, height, **options) = Texture.new(width, height, **options)
      def create_buffer(size, **options) = Buffer.new(size, **options)
      def create_pipeline(shader:, blend: :premultiplied) = Pipeline.new(shader, blend)
      def begin_frame(clear: "#0000") = FrameEncoder.new(self, clear)

      def render(scene, clear: "#0000")
        pool = O.new("NSAutoreleasePool")
        @draw_calls = 0
        drawable = O.send(@window.layer, "nextDrawable")
        return if drawable.zero?
        target = O.send(drawable, "texture")
        O.release(@last_texture) if @last_texture
        @last_texture = O.send(target, "retain")
        command = O.send(@queue, "commandBuffer")
        O.send(@color_attachment, "setTexture:", target, args: POINTER_ARGS, result: :void)
        unless clear == @clear_input
          O.send(@color_attachment, "setClearColor:", Color.parse(clear).premultiplied, args: CLEAR_ARGS, result: :void)
          @clear_input = clear.is_a?(String) || clear.is_a?(Array) ? clear.dup.freeze : clear
        end
        encoder = O.send(command, "renderCommandEncoderWithDescriptor:", @render_pass, args: POINTER_ARGS)
        O.send(encoder, "setRenderPipelineState:", @pipeline, args: POINTER_ARGS, result: :void)
        bytes, batches = InstancePacking.pack(scene)
        unless bytes.empty?
          buffer = O.send(@device, "newBufferWithBytes:length:options:", Fiddle::Pointer[bytes], bytes.bytesize, 0, args: BUFFER_ARGS)
          O.send(encoder, "setVertexBytes:length:atIndex:", @viewport_pointer, @viewport_bytes.bytesize, 1, args: BUFFER_ARGS, result: :void)
          batches.each do |(kind, texture, clip), first, count|
            scissor = @full_scissor
            if clip
              left, top = [clip.x, 0].max, [clip.y, 0].max
              width, height = [clip.right, @width].min - left, [clip.bottom, @height].min - top
              next unless width.positive? && height.positive?
              scissor = @scissor
              scissor[0], scissor[1] = (left * @scale).to_i, (top * @scale).to_i
              scissor[2], scissor[3] = (width * @scale).to_i, (height * @scale).to_i
            end
            next if scissor[2].zero? || scissor[3].zero?
            # MTLScissorRect is four NSUInteger values, the same layout as two ranges.
            @scissor_signature.call(O::MESSAGE_SEND, encoder, @scissor_selector, scissor)
            O.send(encoder, "setVertexBuffer:offset:atIndex:", buffer, first * InstancePacking::STRIDE * 4, 0, args: BUFFER_ARGS, result: :void)
            O.send(encoder, "setFragmentTexture:atIndex:", native_texture(texture || @white), 0, args: TEXTURE_ARGS, result: :void)
            O.send(encoder, "drawPrimitives:vertexStart:vertexCount:instanceCount:", kind == :triangle ? 3 : 4, 0, kind == :triangle ? 3 : 4, count, args: DRAW_ARGS, result: :void)
            @draw_calls += 1
          end
        end
        O.send(encoder, "endEncoding", result: :void)
        O.send(command, "presentDrawable:", drawable, args: POINTER_ARGS, result: :void)
        O.send(command, "commit", result: :void)
        O.release(@last_command) if @last_command
        @last_command = O.send(command, "retain")
      ensure
        O.release(buffer) if buffer
        O.release(pool) if pool
      end

      def native_texture(texture)
        entry = @textures[texture]
        unless entry
          descriptor = O.send(O.klass("MTLTextureDescriptor"), "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", texture.format == :r8 ? 10 : 70, texture.width, texture.height, 0, args: [:ulong, :ulong, :ulong, :bool])
          O.send(descriptor, "setStorageMode:", 0, args: [:ulong], result: :void)
          entry = @textures[texture] = [O.send(@device, "newTextureWithDescriptor:", descriptor, args: [:pointer]), nil]
          raise Error, "Metal texture allocation failed" if entry[0].zero?
        end
        digest = texture.revision
        if entry[1] != digest
          region = [0, 0, 0, texture.width, texture.height, 1]
          O.send(entry[0], "replaceRegion:mipmapLevel:withBytes:bytesPerRow:", region, 0, Fiddle::Pointer[texture.data], texture.width * (texture.format == :r8 ? 1 : 4), args: [:region, :ulong, :pointer, :ulong], result: :void)
          entry[1] = digest
        end
        entry[0]
      end

      def pixels
        return "\0".b * (@pixel_width * @pixel_height * 4) unless @last_texture
        O.send(@last_command, "waitUntilCompleted", result: :void)
        status = O.send(@last_command, "status", result: :ulong)
        raise Error, O.text(O.send(O.send(@last_command, "error"), "localizedDescription")) if status == 5
        bytes = "\0".b * (@pixel_width * @pixel_height * 4)
        O.send(@last_texture, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", Fiddle::Pointer[bytes], @pixel_width * 4, [0, 0, 0, @pixel_width, @pixel_height, 1], 0, args: [:pointer, :ulong, :region, :ulong], result: :void)
        bytes.unpack("C*").each_slice(4).flat_map { |b, g, r, a| a.zero? ? [0, 0, 0, 0] : [(r * 255 / a).clamp(0, 255), (g * 255 / a).clamp(0, 255), (b * 255 / a).clamp(0, 255), a] }.pack("C*")
      end
      def write_png(path) = PNG.write(path, @pixel_width, @pixel_height, pixels)
      def release
        O.send(@last_command, "waitUntilCompleted", result: :void) if @last_command
        @textures.each_value { |entry| O.release(entry[0]) }
        @textures.clear
        [@last_command, @last_texture, @render_pass, @pipeline, @queue, @device].compact.each { |object| O.release(object) }
        @last_command = @last_texture = @render_pass = nil
      end
      def native_error(pointer, fallback)
        object = pointer[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
        object.zero? ? fallback : O.text(O.send(object, "localizedDescription"))
      end
    end
  end
end
