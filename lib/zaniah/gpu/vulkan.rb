# frozen_string_literal: true

require "fiddle/import"
require_relative "../ffi/library"

module Zaniah
  module GPU
    # Minimal offscreen Vulkan path for validating the pure Ruby SPIR-V emitter.
    # It renders a vertex-index triangle into RGBA8 and reads back native memory.
    # Window presentation and general Scene rendering remain Metal/OpenGL work.
    class Vulkan
      module Types
        extend Fiddle::Importer
        Instance = struct ["int s_type", "void *next", "unsigned int flags", "void *application", "unsigned int layer_count", "void *layers", "unsigned int extension_count", "void *extensions"]
        Queue = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int family", "unsigned int count", "void *priorities"]
        Device = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int queue_count", "void *queues", "unsigned int layer_count", "void *layers", "unsigned int extension_count", "void *extensions", "void *features"]
        Image = struct ["int s_type", "void *next", "unsigned int flags", "int image_type", "int format", "unsigned int width", "unsigned int height", "unsigned int depth", "unsigned int mip_levels", "unsigned int layers", "unsigned int samples", "int tiling", "unsigned int usage", "int sharing", "unsigned int family_count", "void *families", "int initial_layout"]
        Buffer = struct ["int s_type", "void *next", "unsigned int flags", "unsigned long long size", "unsigned int usage", "int sharing", "unsigned int family_count", "void *families"]
        Allocation = struct ["int s_type", "void *next", "unsigned long long size", "unsigned int type_index"]
        ImageView = struct ["int s_type", "void *next", "unsigned int flags", "unsigned long long image", "int view_type", "int format", "int components[4]", "unsigned int aspect", "unsigned int mip_level", "unsigned int level_count", "unsigned int array_layer", "unsigned int layer_count"]
        Attachment = struct ["unsigned int flags", "int format", "unsigned int samples", "int load", "int store", "int stencil_load", "int stencil_store", "int initial_layout", "int final_layout"]
        Subpass = struct ["unsigned int flags", "int bind_point", "unsigned int input_count", "void *inputs", "unsigned int color_count", "void *colors", "void *resolves", "void *depth_stencil", "unsigned int preserve_count", "void *preserves"]
        Dependency = struct ["unsigned int source", "unsigned int destination", "unsigned int source_stage", "unsigned int destination_stage", "unsigned int source_access", "unsigned int destination_access", "unsigned int flags"]
        RenderPass = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int attachment_count", "void *attachments", "unsigned int subpass_count", "void *subpasses", "unsigned int dependency_count", "void *dependencies"]
        Framebuffer = struct ["int s_type", "void *next", "unsigned int flags", "unsigned long long render_pass", "unsigned int attachment_count", "void *attachments", "unsigned int width", "unsigned int height", "unsigned int layers"]
        Shader = struct ["int s_type", "void *next", "unsigned int flags", "size_t code_size", "void *code"]
        Stage = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int stage", "unsigned long long shader", "void *name", "void *specialization"]
        VertexInput = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int binding_count", "void *bindings", "unsigned int attribute_count", "void *attributes"]
        Assembly = struct ["int s_type", "void *next", "unsigned int flags", "int topology", "unsigned int primitive_restart"]
        Viewport = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int viewport_count", "void *viewports", "unsigned int scissor_count", "void *scissors"]
        Rasterization = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int depth_clamp", "unsigned int discard", "int polygon_mode", "unsigned int cull_mode", "int front_face", "unsigned int depth_bias", "float depth_bias_constant", "float depth_bias_clamp", "float depth_bias_slope", "float line_width"]
        Multisample = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int samples", "unsigned int sample_shading", "float min_sample_shading", "void *sample_mask", "unsigned int alpha_to_coverage", "unsigned int alpha_to_one"]
        Blend = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int logic_enable", "int logic_op", "unsigned int attachment_count", "void *attachments", "float constants[4]"]
        Layout = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int set_count", "void *sets", "unsigned int push_count", "void *pushes"]
        Pipeline = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int stage_count", "void *stages", "void *vertex_input", "void *assembly", "void *tessellation", "void *viewport", "void *rasterization", "void *multisample", "void *depth_stencil", "void *blend", "void *dynamic", "unsigned long long layout", "unsigned long long render_pass", "unsigned int subpass", "unsigned long long base_pipeline", "int base_index"]
        CommandPool = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int family"]
        CommandAllocation = struct ["int s_type", "void *next", "unsigned long long pool", "int level", "unsigned int count"]
        CommandBegin = struct ["int s_type", "void *next", "unsigned int flags", "void *inheritance"]
        RenderBegin = struct ["int s_type", "void *next", "unsigned long long render_pass", "unsigned long long framebuffer", "int x", "int y", "unsigned int width", "unsigned int height", "unsigned int clear_count", "void *clears"]
        MemoryBarrier = struct ["int s_type", "void *next", "unsigned int source_access", "unsigned int destination_access"]
        Fence = struct ["int s_type", "void *next", "unsigned int flags"]
        Submit = struct ["int s_type", "void *next", "unsigned int wait_count", "void *wait_semaphores", "void *wait_stages", "unsigned int command_count", "void *commands", "unsigned int signal_count", "void *signal_semaphores"]
      end

      P, I, U, Q, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, -Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOID
      attr_reader :width, :height, :pixels, :device_name

      def initialize(width: 128, height: 128)
        raise ArgumentError, "invalid Vulkan image dimensions" unless [width, height].all? { |n| n.is_a?(Integer) && n.positive? } && width * height <= 16_777_216
        @width, @height, @arena, @resources, @memories = width, height, [], [], []
        @lib = FFI::Library.new("libvulkan.so.1", "vulkan-1.dll", "libvulkan.1.dylib", "libMoltenVK.dylib")
        output = keep("\0".b * 8)
        check(call(:vkCreateInstance, [P, P, P], I, build(Types::Instance, s_type: 1), 0, output), "vkCreateInstance")
        @instance = output.unpack1("J")
        count = keep([0].pack("I"))
        check(call(:vkEnumeratePhysicalDevices, [P, P, P], I, @instance, count, 0), "vkEnumeratePhysicalDevices")
        raise Error, "no Vulkan physical device" if count.unpack1("I").zero?
        physicals = keep("\0".b * (count.unpack1("I") * Fiddle::SIZEOF_VOIDP))
        check(call(:vkEnumeratePhysicalDevices, [P, P, P], I, @instance, count, physicals), "vkEnumeratePhysicalDevices")
        @physical = physicals.unpack1("J")
        properties = keep("\0".b * 4096)
        call(:vkGetPhysicalDeviceProperties, [P, P], V, @physical, properties)
        @device_name = properties.byteslice(20, 256).split("\0", 2).first
        count.replace([0].pack("I"))
        call(:vkGetPhysicalDeviceQueueFamilyProperties, [P, P, P], V, @physical, count, 0)
        families = keep("\0".b * (count.unpack1("I") * 24))
        call(:vkGetPhysicalDeviceQueueFamilyProperties, [P, P, P], V, @physical, count, families)
        @family = count.unpack1("I").times.find { |index| (families.byteslice(index * 24, 4).unpack1("I") & 1) != 0 }
        raise Error, "no Vulkan graphics queue" unless @family
        queue_info = build(Types::Queue, s_type: 2, family: @family, count: 1, priorities: keep([1.0].pack("f")))
        info = build(Types::Device, s_type: 3, queue_count: 1, queues: queue_info)
        check(call(:vkCreateDevice, [P, P, P, P], I, @physical, info, 0, output), "vkCreateDevice")
        @device = output.unpack1("J")
        call(:vkGetDeviceQueue, [P, U, U, P], V, @device, @family, 0, output)
        @queue = output.unpack1("J")
        @memory_properties = keep("\0".b * 1024)
        call(:vkGetPhysicalDeviceMemoryProperties, [P, P], V, @physical, @memory_properties)
        create_target
      rescue StandardError, LoadError
        release
        raise
      end

      def keep(object)
        @arena << object
        object
      end
      def build(type, **values)
        object = type.malloc(Fiddle::RUBY_FREE)
        object.to_ptr[0, type.size] = "\0" * type.size
        values.each { |name, value| object[name.to_s] = value.is_a?(String) ? Fiddle::Pointer[value] : value }
        keep(object)
      end
      def call(name, arguments, result, *values) = @lib.fn(name, arguments, result, need_gvl: false).call(*values)
      def check(result, name)
        raise Error, "#{name} failed with VkResult #{result}" unless result.zero?
        result
      end
      def create(kind, info)
        output = keep("\0".b * 8)
        check(call("vkCreate#{kind}", [P, P, P, P], I, @device, info, 0, output), "vkCreate#{kind}")
        handle = output.unpack1("Q")
        @resources << ["vkDestroy#{kind}", handle]
        handle
      end
      def allocate_for(kind, handle, required_flags:)
        requirements = keep("\0".b * 24)
        call("vkGet#{kind}MemoryRequirements", [P, Q, P], V, @device, handle, requirements)
        size, _alignment, bits = requirements.unpack("QQI")
        count = @memory_properties.unpack1("I")
        index = count.times.find do |n|
          flags = @memory_properties.byteslice(4 + n * 8, 4).unpack1("I")
          (bits & (1 << n)) != 0 && (flags & required_flags) == required_flags
        end
        raise Error, "Vulkan memory type unavailable (flags #{required_flags})" unless index
        output = keep("\0".b * 8)
        info = build(Types::Allocation, s_type: 5, size: size, type_index: index)
        check(call(:vkAllocateMemory, [P, P, P, P], I, @device, info, 0, output), "vkAllocateMemory")
        memory = output.unpack1("Q")
        @memories << memory
        check(call("vkBind#{kind}Memory", [P, Q, Q, Q], I, @device, handle, memory, 0), "vkBind#{kind}Memory")
        memory
      end
      def create_target
        @image = create("Image", build(Types::Image, s_type: 14, image_type: 1, format: 37,
          width: @width, height: @height, depth: 1, mip_levels: 1, layers: 1, samples: 1, usage: 0x11))
        allocate_for("Image", @image, required_flags: 0)
        @view = create("ImageView", build(Types::ImageView, s_type: 15, image: @image, view_type: 1,
          format: 37, aspect: 1, level_count: 1, layer_count: 1))
        attachment = build(Types::Attachment, format: 37, samples: 1, load: 1, store: 0,
          stencil_load: 2, stencil_store: 1, initial_layout: 0, final_layout: 6)
        reference = keep([0, 2].pack("I2"))
        subpass = build(Types::Subpass, color_count: 1, colors: reference)
        incoming = build(Types::Dependency, source: 0xffffffff, destination: 0, source_stage: 1,
          destination_stage: 0x400, destination_access: 0x100)
        outgoing = build(Types::Dependency, source: 0, destination: 0xffffffff, source_stage: 0x400,
          destination_stage: 0x1000, source_access: 0x100, destination_access: 0x800)
        dependencies = keep(incoming.to_ptr[0, Types::Dependency.size] + outgoing.to_ptr[0, Types::Dependency.size])
        @render_pass = create("RenderPass", build(Types::RenderPass, s_type: 38,
          attachment_count: 1, attachments: attachment, subpass_count: 1, subpasses: subpass,
          dependency_count: 2, dependencies: dependencies))
        @framebuffer = create("Framebuffer", build(Types::Framebuffer, s_type: 37, render_pass: @render_pass,
          attachment_count: 1, attachments: keep([@view].pack("Q")), width: @width, height: @height, layers: 1))
        @buffer = create("Buffer", build(Types::Buffer, s_type: 12, size: @width * @height * 4, usage: 2))
        @read_memory = allocate_for("Buffer", @buffer, required_flags: 6)
        @pool = create("CommandPool", build(Types::CommandPool, s_type: 39, flags: 2, family: @family))
        @layout = create("PipelineLayout", build(Types::Layout, s_type: 30))
      end

      def shader(bytes)
        unless bytes.is_a?(String) && bytes.bytesize.between?(20, 16_777_216) && (bytes.bytesize % 4).zero? && bytes.unpack1("V") == 0x07230203
          raise ArgumentError, "expected a SPIR-V word stream"
        end
        create("ShaderModule", build(Types::Shader, s_type: 16, code_size: bytes.bytesize, code: keep(bytes)))
      end
      def pipeline(vertex_spirv, fragment_spirv)
        vertex = build(Types::Stage, s_type: 18, stage: 1, shader: shader(vertex_spirv), name: keep("main\0"))
        fragment = build(Types::Stage, s_type: 18, stage: 16, shader: shader(fragment_spirv), name: keep("main\0"))
        stages = keep(vertex.to_ptr[0, Types::Stage.size] + fragment.to_ptr[0, Types::Stage.size])
        vertex_input = build(Types::VertexInput, s_type: 19)
        assembly = build(Types::Assembly, s_type: 20, topology: 3)
        viewport = keep([0, 0, @width, @height, 0, 1].pack("f6"))
        scissor = keep([0, 0, @width, @height].pack("i2I2"))
        viewport_state = build(Types::Viewport, s_type: 22, viewport_count: 1, viewports: viewport, scissor_count: 1, scissors: scissor)
        raster = build(Types::Rasterization, s_type: 23, front_face: 1, line_width: 1.0)
        multisample = build(Types::Multisample, s_type: 24, samples: 1)
        blend_attachment = keep([0, 1, 0, 0, 1, 0, 0, 15].pack("I8"))
        blend = build(Types::Blend, s_type: 26, attachment_count: 1, attachments: blend_attachment)
        info = build(Types::Pipeline, s_type: 28, stage_count: 2, stages: stages,
          vertex_input: vertex_input, assembly: assembly, viewport: viewport_state,
          rasterization: raster, multisample: multisample, blend: blend, layout: @layout,
          render_pass: @render_pass, base_index: -1)
        output = keep("\0".b * 8)
        check(call(:vkCreateGraphicsPipelines, [P, Q, U, P, P, P], I, @device, 0, 1, info, 0, output), "vkCreateGraphicsPipelines")
        result = output.unpack1("Q")
        @resources << [:vkDestroyPipeline, result]
        result
      end

      def render_triangle(vertex_spirv:, fragment_spirv:)
        raise IOError, "Vulkan device released" unless @device
        # ponytail: validation submissions retain resources until release;
        # recycle pipelines/command buffers before using this as a frame loop.
        pipeline_handle = pipeline(vertex_spirv, fragment_spirv)
        output = keep("\0".b * 8)
        info = build(Types::CommandAllocation, s_type: 40, pool: @pool, level: 0, count: 1)
        check(call(:vkAllocateCommandBuffers, [P, P, P], I, @device, info, output), "vkAllocateCommandBuffers")
        command = output.unpack1("J")
        check(call(:vkBeginCommandBuffer, [P, P], I, command, build(Types::CommandBegin, s_type: 42, flags: 1)), "vkBeginCommandBuffer")
        render = build(Types::RenderBegin, s_type: 43, render_pass: @render_pass, framebuffer: @framebuffer,
          width: @width, height: @height, clear_count: 1, clears: keep([0, 0, 0, 1].pack("f4")))
        call(:vkCmdBeginRenderPass, [P, P, I], V, command, render, 0)
        call(:vkCmdBindPipeline, [P, I, Q], V, command, 0, pipeline_handle)
        call(:vkCmdDraw, [P, U, U, U, U], V, command, 3, 1, 0, 0)
        call(:vkCmdEndRenderPass, [P], V, command)
        region = keep([0, 0, 0, 1, 0, 0, 1, 0, 0, 0, @width, @height, 1].pack("Q I2 I4 i3 I3"))
        call(:vkCmdCopyImageToBuffer, [P, Q, I, Q, U, P], V, command, @image, 6, @buffer, 1, region)
        barrier = build(Types::MemoryBarrier, s_type: 46, source_access: 0x1000, destination_access: 0x2000)
        call(:vkCmdPipelineBarrier, [P, U, U, U, U, P, U, P, U, P], V, command, 0x1000, 0x4000, 0, 1, barrier, 0, 0, 0, 0)
        check(call(:vkEndCommandBuffer, [P], I, command), "vkEndCommandBuffer")
        fence = create("Fence", build(Types::Fence, s_type: 8))
        submit = build(Types::Submit, s_type: 4, command_count: 1, commands: keep([command].pack("J")))
        check(call(:vkQueueSubmit, [P, U, P, Q], I, @queue, 1, submit, fence), "vkQueueSubmit")
        check(call(:vkWaitForFences, [P, U, P, U, Q], I, @device, 1, keep([fence].pack("Q")), 1, 10_000_000_000), "vkWaitForFences")
        check(call(:vkMapMemory, [P, Q, Q, Q, U, P], I, @device, @read_memory, 0, @width * @height * 4, 0, output), "vkMapMemory")
        begin
          @pixels = Fiddle::Pointer.new(output.unpack1("J"))[0, @width * @height * 4]
        ensure
          call(:vkUnmapMemory, [P, Q], V, @device, @read_memory)
        end
        @pixels
      end
      def write_png(path)
        raise Error, "render a Vulkan frame before capture" unless @pixels
        PNG.write(path, @width, @height, @pixels)
      end
      def release
        if @device
          call(:vkDeviceWaitIdle, [P], I, @device)
          @resources.reverse_each { |name, handle| call(name, [P, Q, P], V, @device, handle, 0) }
          @memories.each { |memory| call(:vkFreeMemory, [P, Q, P], V, @device, memory, 0) }
          call(:vkDestroyDevice, [P, P], V, @device, 0)
          @device = nil
        end
        call(:vkDestroyInstance, [P, P], V, @instance, 0) if @instance
        @instance = nil
        @resources&.clear
        @memories&.clear
        @arena&.clear
      end
    end
  end
end
