# frozen_string_literal: true

require "fiddle/import"
require_relative "../ffi/library"
require_relative "instance_packing"

module Zaniah
  module GPU
    # Offscreen Vulkan renderer and user-supplied SPIR-V validation path.
    class Vulkan
      INSTANCE_STRIDE = InstancePacking::STRIDE
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
        VertexBinding = struct ["unsigned int binding", "unsigned int stride", "int input_rate"]
        VertexAttribute = struct ["unsigned int location", "unsigned int binding", "int format", "unsigned int offset"]
        Assembly = struct ["int s_type", "void *next", "unsigned int flags", "int topology", "unsigned int primitive_restart"]
        Viewport = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int viewport_count", "void *viewports", "unsigned int scissor_count", "void *scissors"]
        Rasterization = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int depth_clamp", "unsigned int discard", "int polygon_mode", "unsigned int cull_mode", "int front_face", "unsigned int depth_bias", "float depth_bias_constant", "float depth_bias_clamp", "float depth_bias_slope", "float line_width"]
        Multisample = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int samples", "unsigned int sample_shading", "float min_sample_shading", "void *sample_mask", "unsigned int alpha_to_coverage", "unsigned int alpha_to_one"]
        Blend = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int logic_enable", "int logic_op", "unsigned int attachment_count", "void *attachments", "float constants[4]"]
        Dynamic = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int count", "void *states"]
        PushConstant = struct ["unsigned int stage_flags", "unsigned int offset", "unsigned int size"]
        Layout = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int set_count", "void *sets", "unsigned int push_count", "void *pushes"]
        Pipeline = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int stage_count", "void *stages", "void *vertex_input", "void *assembly", "void *tessellation", "void *viewport", "void *rasterization", "void *multisample", "void *depth_stencil", "void *blend", "void *dynamic", "unsigned long long layout", "unsigned long long render_pass", "unsigned int subpass", "unsigned long long base_pipeline", "int base_index"]
        CommandPool = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int family"]
        CommandAllocation = struct ["int s_type", "void *next", "unsigned long long pool", "int level", "unsigned int count"]
        CommandBegin = struct ["int s_type", "void *next", "unsigned int flags", "void *inheritance"]
        RenderBegin = struct ["int s_type", "void *next", "unsigned long long render_pass", "unsigned long long framebuffer", "int x", "int y", "unsigned int width", "unsigned int height", "unsigned int clear_count", "void *clears"]
        MemoryBarrier = struct ["int s_type", "void *next", "unsigned int source_access", "unsigned int destination_access"]
        ImageBarrier = struct ["int s_type", "void *next", "unsigned int source_access", "unsigned int destination_access", "int old_layout", "int new_layout", "unsigned int source_family", "unsigned int destination_family", "unsigned long long image", "unsigned int aspect", "unsigned int mip_level", "unsigned int level_count", "unsigned int array_layer", "unsigned int layer_count"]
        Fence = struct ["int s_type", "void *next", "unsigned int flags"]
        Submit = struct ["int s_type", "void *next", "unsigned int wait_count", "void *wait_semaphores", "void *wait_stages", "unsigned int command_count", "void *commands", "unsigned int signal_count", "void *signal_semaphores"]
        DescriptorBinding = struct ["unsigned int binding", "int descriptor_type", "unsigned int count", "unsigned int stage_flags", "void *immutable_samplers"]
        DescriptorLayout = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int count", "void *bindings"]
        DescriptorPoolSize = struct ["int descriptor_type", "unsigned int count"]
        DescriptorPool = struct ["int s_type", "void *next", "unsigned int flags", "unsigned int max_sets", "unsigned int count", "void *sizes"]
        DescriptorAllocation = struct ["int s_type", "void *next", "unsigned long long pool", "unsigned int count", "void *layouts"]
        DescriptorImage = struct ["unsigned long long sampler", "unsigned long long view", "int layout"]
        DescriptorWrite = struct ["int s_type", "void *next", "unsigned long long set", "unsigned int binding", "unsigned int array_element", "unsigned int count", "int descriptor_type", "void *images", "void *buffers", "void *texel_views"]
        Sampler = struct ["int s_type", "void *next", "unsigned int flags", "int mag_filter", "int min_filter", "int mipmap_mode", "int address_u", "int address_v", "int address_w", "float mip_lod_bias", "unsigned int anisotropy", "float max_anisotropy", "unsigned int compare", "int compare_op", "float min_lod", "float max_lod", "int border_color", "unsigned int unnormalized"]
      end

      P, I, U, Q, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, -Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOID
      attr_reader :width, :height, :pixels, :device_name, :draw_calls

      def initialize(width: 128, height: 128)
        raise ArgumentError, "invalid Vulkan image dimensions" unless [width, height].all? { |n| n.is_a?(Integer) && n.positive? } && width * height <= 16_777_216
        @width, @height, @arena, @resources, @memories, @native_textures = width, height, [], [], [], {}
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
        binding = build(Types::DescriptorBinding, descriptor_type: 1, count: 1, stage_flags: 16)
        @descriptor_layout = create("DescriptorSetLayout",
          build(Types::DescriptorLayout, s_type: 32, count: 1, bindings: binding))
        pool_size = build(Types::DescriptorPoolSize, descriptor_type: 1, count: 4096)
        @descriptor_pool = create("DescriptorPool",
          build(Types::DescriptorPool, s_type: 33, max_sets: 4096, count: 1, sizes: pool_size))
        @sampler = create("Sampler", build(Types::Sampler, s_type: 31, mag_filter: 0, min_filter: 0,
          mipmap_mode: 0, address_u: 2, address_v: 2, address_w: 2, max_lod: 1.0))
        push = build(Types::PushConstant, stage_flags: 1, size: 8)
        @layout = create("PipelineLayout", build(Types::Layout, s_type: 30,
          set_count: 1, sets: keep([@descriptor_layout].pack("Q")), push_count: 1, pushes: push))
        @white = Texture.new(1, 1, data: "\xff".b * 4)
      end

      def shader(bytes)
        unless bytes.is_a?(String) && bytes.bytesize.between?(20, 16_777_216) && (bytes.bytesize % 4).zero? && bytes.unpack1("V") == 0x07230203
          raise ArgumentError, "expected a SPIR-V word stream"
        end
        create("ShaderModule", build(Types::Shader, s_type: 16, code_size: bytes.bytesize, code: keep(bytes)))
      end
      def pipeline(vertex_spirv, fragment_spirv, topology: 3, instanced: false)
        vertex_shader, fragment_shader = shader(vertex_spirv), shader(fragment_spirv)
        vertex = build(Types::Stage, s_type: 18, stage: 1, shader: vertex_shader, name: keep("main\0"))
        fragment = build(Types::Stage, s_type: 18, stage: 16, shader: fragment_shader, name: keep("main\0"))
        stages = keep(vertex.to_ptr[0, Types::Stage.size] + fragment.to_ptr[0, Types::Stage.size])
        vertex_input = if instanced
          binding = build(Types::VertexBinding, stride: INSTANCE_STRIDE * 4, input_rate: 1)
          attributes = 10.times.map do |location|
            value = build(Types::VertexAttribute, location: location, format: 109, offset: location * 16)
            value.to_ptr[0, Types::VertexAttribute.size]
          end.join
          build(Types::VertexInput, s_type: 19, binding_count: 1, bindings: binding,
            attribute_count: 10, attributes: keep(attributes))
        else
          build(Types::VertexInput, s_type: 19)
        end
        assembly = build(Types::Assembly, s_type: 20, topology: topology)
        viewport = keep([0, 0, @width, @height, 0, 1].pack("f6"))
        scissor = keep([0, 0, @width, @height].pack("i2I2"))
        viewport_state = build(Types::Viewport, s_type: 22, viewport_count: 1, viewports: viewport, scissor_count: 1, scissors: scissor)
        raster = build(Types::Rasterization, s_type: 23, front_face: 1, line_width: 1.0)
        multisample = build(Types::Multisample, s_type: 24, samples: 1)
        blend_attachment = keep([1, 1, 7, 0, 1, 7, 0, 15].pack("I8"))
        blend = build(Types::Blend, s_type: 26, attachment_count: 1, attachments: blend_attachment)
        dynamic = build(Types::Dynamic, s_type: 27, count: 1, states: keep([1].pack("I")))
        info = build(Types::Pipeline, s_type: 28, stage_count: 2, stages: stages,
          vertex_input: vertex_input, assembly: assembly, viewport: viewport_state,
          rasterization: raster, multisample: multisample, blend: blend, dynamic: dynamic, layout: @layout,
          render_pass: @render_pass, base_index: -1)
        output = keep("\0".b * 8)
        check(call(:vkCreateGraphicsPipelines, [P, Q, U, P, P, P], I, @device, 0, 1, info, 0, output), "vkCreateGraphicsPipelines")
        result = output.unpack1("Q")
        @resources << [:vkDestroyPipeline, result]
        result
      ensure
        destroy_resource(:vkDestroyShaderModule, vertex_shader) if vertex_shader
        destroy_resource(:vkDestroyShaderModule, fragment_shader) if fragment_shader
      end

      def render(scene, clear: "#0000")
        raise IOError, "Vulkan device released" unless @device
        bytes, batches = InstancePacking.pack(scene)
        command = begin_command
        transients = []
        descriptors = batches.map { |(_kind, texture, _clip), _first, _count| prepare_texture(texture || @white, command, transients) }
        upload_instances(bytes) unless bytes.empty?
        render_pass(command, clear)
        @draw_calls = 0
        unless bytes.empty?
          call(:vkCmdBindVertexBuffers, [P, U, U, P, P], V, command, 0, 1,
            keep([@instance_buffer].pack("Q")), keep([0].pack("Q")))
          call(:vkCmdPushConstants, [P, Q, U, U, U, P], V, command, @layout, 1, 0, 8,
            keep([@width.to_f, @height.to_f].pack("f2")))
          batches.each_with_index do |((kind, _texture, clip), first, count), index|
            scissor = scissor_bytes(clip)
            next unless scissor
            call(:vkCmdSetScissor, [P, U, U, P], V, command, 0, 1, keep(scissor))
            pipeline_handle = scene_pipeline(kind)
            call(:vkCmdBindPipeline, [P, I, Q], V, command, 0, pipeline_handle)
            descriptor = descriptors[index]
            call(:vkCmdBindDescriptorSets, [P, I, Q, U, U, P, U, P], V,
              command, 0, @layout, 0, 1, keep([descriptor].pack("Q")), 0, 0)
            vertices = kind == :triangle ? 3 : 4
            call(:vkCmdDraw, [P, U, U, U, U], V, command, vertices, count, 0, first)
            @draw_calls += 1
          end
        end
        call(:vkCmdEndRenderPass, [P], V, command)
        copy_target(command)
        @pixels = submit(command, read: true)
      ensure
        transients&.each { |buffer, memory| destroy_buffer_memory(buffer, memory) }
      end

      def resize(width, height)
        width, height = Integer(width), Integer(height)
        return if width == @width && height == @height
        release
        initialize(width: width, height: height)
      end
      def create_texture(width, height, **options) = Texture.new(width, height, **options)
      def create_buffer(size, **options) = Buffer.new(size, **options)
      def create_pipeline(shader:, blend: :premultiplied) = Pipeline.new(shader, blend)
      def begin_frame(clear: "#0000") = FrameEncoder.new(self, clear)

      def scene_pipeline(kind)
        topology = kind == :triangle ? 3 : 4
        (@scene_pipelines ||= {})[topology] ||= begin
          directory = File.join(__dir__, "vulkan")
          pipeline(File.binread(File.join(directory, "scene.vert.spv")),
            File.binread(File.join(directory, "scene.frag.spv")), topology: topology, instanced: true)
        end
      end

      def begin_command
        output = keep("\0".b * 8)
        info = build(Types::CommandAllocation, s_type: 40, pool: @pool, level: 0, count: 1)
        check(call(:vkAllocateCommandBuffers, [P, P, P], I, @device, info, output), "vkAllocateCommandBuffers")
        command = output.unpack1("J")
        check(call(:vkBeginCommandBuffer, [P, P], I, command,
          build(Types::CommandBegin, s_type: 42, flags: 1)), "vkBeginCommandBuffer")
        command
      end

      def render_pass(command, clear)
        color = Color.parse(clear).premultiplied
        info = build(Types::RenderBegin, s_type: 43, render_pass: @render_pass, framebuffer: @framebuffer,
          width: @width, height: @height, clear_count: 1, clears: keep(color.pack("f4")))
        call(:vkCmdBeginRenderPass, [P, P, I], V, command, info, 0)
      end

      def upload_instances(bytes)
        if !@instance_buffer || @instance_capacity < bytes.bytesize
          destroy_buffer_memory(@instance_buffer, @instance_memory) if @instance_buffer
          @instance_capacity = [bytes.bytesize, 4096].max
          @instance_buffer = create("Buffer", build(Types::Buffer, s_type: 12,
            size: @instance_capacity, usage: 0x80))
          @instance_memory = allocate_for("Buffer", @instance_buffer, required_flags: 6)
        end
        output = keep("\0".b * 8)
        check(call(:vkMapMemory, [P, Q, Q, Q, U, P], I, @device, @instance_memory,
          0, bytes.bytesize, 0, output), "vkMapMemory")
        Fiddle::Pointer.new(output.unpack1("J"))[0, bytes.bytesize] = bytes
        call(:vkUnmapMemory, [P, Q], V, @device, @instance_memory)
      end

      def prepare_texture(texture, command, transients)
        entry = @native_textures[texture]
        return entry[:descriptor] if entry && entry[:revision] == texture.revision
        if entry
          destroy_resource(:vkDestroyImageView, entry[:view])
          destroy_resource(:vkDestroyImage, entry[:image])
          free_memory(entry[:memory])
        else
          output = keep("\0".b * 8)
          info = build(Types::DescriptorAllocation, s_type: 34, pool: @descriptor_pool,
            count: 1, layouts: keep([@descriptor_layout].pack("Q")))
          check(call(:vkAllocateDescriptorSets, [P, P, P], I, @device, info, output), "vkAllocateDescriptorSets")
          entry = {descriptor: output.unpack1("Q")}
          @native_textures[texture] = entry
        end
        entry[:image] = create("Image", build(Types::Image, s_type: 14, image_type: 1,
          format: texture.format == :r8 ? 9 : 37, width: texture.width, height: texture.height,
          depth: 1, mip_levels: 1, layers: 1, samples: 1, usage: 6))
        entry[:memory] = allocate_for("Image", entry[:image], required_flags: 0)
        entry[:view] = create("ImageView", build(Types::ImageView, s_type: 15, image: entry[:image],
          view_type: 1, format: texture.format == :r8 ? 9 : 37, aspect: 1, level_count: 1, layer_count: 1))
        staging = create("Buffer", build(Types::Buffer, s_type: 12, size: texture.data.bytesize, usage: 1))
        staging_memory = allocate_for("Buffer", staging, required_flags: 6)
        upload_memory(staging_memory, texture.data)
        transition_image(command, entry[:image], 0, 7, 0, 0x1000, 1, 0x1000)
        region = keep([0, 0, 0, 1, 0, 0, 1, 0, 0, 0, texture.width, texture.height, 1].pack("Q I2 I4 i3 I3"))
        call(:vkCmdCopyBufferToImage, [P, Q, Q, I, U, P], V,
          command, staging, entry[:image], 7, 1, region)
        transition_image(command, entry[:image], 7, 5, 0x1000, 0x20, 0x1000, 0x80)
        image = build(Types::DescriptorImage, sampler: @sampler, view: entry[:view], layout: 5)
        write = build(Types::DescriptorWrite, s_type: 35, set: entry[:descriptor], count: 1,
          descriptor_type: 1, images: image)
        call(:vkUpdateDescriptorSets, [P, U, P, U, P], V, @device, 1, write, 0, 0)
        entry[:revision] = texture.revision
        transients << [staging, staging_memory]
        entry[:descriptor]
      end

      def upload_memory(memory, bytes)
        output = keep("\0".b * 8)
        check(call(:vkMapMemory, [P, Q, Q, Q, U, P], I, @device, memory,
          0, bytes.bytesize, 0, output), "vkMapMemory")
        Fiddle::Pointer.new(output.unpack1("J"))[0, bytes.bytesize] = bytes
        call(:vkUnmapMemory, [P, Q], V, @device, memory)
      end

      def transition_image(command, image, old_layout, new_layout, source_access, destination_access, source_stage, destination_stage)
        barrier = build(Types::ImageBarrier, s_type: 45, source_access: source_access,
          destination_access: destination_access, old_layout: old_layout, new_layout: new_layout,
          source_family: 0xffffffff, destination_family: 0xffffffff, image: image,
          aspect: 1, level_count: 1, layer_count: 1)
        call(:vkCmdPipelineBarrier, [P, U, U, U, U, P, U, P, U, P], V,
          command, source_stage, destination_stage, 0, 0, 0, 0, 0, 1, barrier)
      end

      def scissor_bytes(clip)
        return [0, 0, @width, @height].pack("i2I2") unless clip
        left, top = [clip.x.floor, 0].max, [clip.y.floor, 0].max
        right, bottom = [clip.right.ceil, @width].min, [clip.bottom.ceil, @height].min
        return if left >= right || top >= bottom
        [left, top, right - left, bottom - top].pack("i2I2")
      end

      def copy_target(command)
        region = keep([0, 0, 0, 1, 0, 0, 1, 0, 0, 0, @width, @height, 1].pack("Q I2 I4 i3 I3"))
        call(:vkCmdCopyImageToBuffer, [P, Q, I, Q, U, P], V,
          command, @image, 6, @buffer, 1, region)
        barrier = build(Types::MemoryBarrier, s_type: 46,
          source_access: 0x1000, destination_access: 0x2000)
        call(:vkCmdPipelineBarrier, [P, U, U, U, U, P, U, P, U, P], V,
          command, 0x1000, 0x4000, 0, 1, barrier, 0, 0, 0, 0)
      end

      def submit(command, read: false)
        check(call(:vkEndCommandBuffer, [P], I, command), "vkEndCommandBuffer")
        fence = create("Fence", build(Types::Fence, s_type: 8))
        info = build(Types::Submit, s_type: 4, command_count: 1, commands: keep([command].pack("J")))
        check(call(:vkQueueSubmit, [P, U, P, Q], I, @queue, 1, info, fence), "vkQueueSubmit")
        check(call(:vkWaitForFences, [P, U, P, U, Q], I, @device, 1,
          keep([fence].pack("Q")), 1, 10_000_000_000), "vkWaitForFences")
        read ? read_target : nil
      ensure
        destroy_resource(:vkDestroyFence, fence) if fence
        call(:vkFreeCommandBuffers, [P, Q, U, P], V,
          @device, @pool, 1, [command].pack("J")) if command && @device
      end

      def read_target
        output = keep("\0".b * 8)
        check(call(:vkMapMemory, [P, Q, Q, Q, U, P], I, @device, @read_memory,
          0, @width * @height * 4, 0, output), "vkMapMemory")
        bytes = Fiddle::Pointer.new(output.unpack1("J"))[0, @width * @height * 4]
        bytes.bytes.each_slice(4).flat_map do |red, green, blue, alpha|
          alpha.zero? ? [0, 0, 0, 0] : [[red * 255 / alpha, 255].min,
            [green * 255 / alpha, 255].min, [blue * 255 / alpha, 255].min, alpha]
        end.pack("C*")
      ensure
        call(:vkUnmapMemory, [P, Q], V, @device, @read_memory) if output&.unpack1("J").to_i.positive?
      end

      def destroy_resource(name, handle)
        return unless handle
        call(name, [P, Q, P], V, @device, handle, 0)
        @resources.delete_if { |_function, value| value == handle }
      end

      def free_memory(memory)
        return unless memory
        call(:vkFreeMemory, [P, Q, P], V, @device, memory, 0)
        @memories.delete(memory)
      end

      def destroy_buffer_memory(buffer, memory)
        destroy_resource(:vkDestroyBuffer, buffer)
        free_memory(memory)
      end

      def render_triangle(vertex_spirv:, fragment_spirv:)
        raise IOError, "Vulkan device released" unless @device
        pipeline_handle = pipeline(vertex_spirv, fragment_spirv)
        command = begin_command
        render_pass(command, "#000f")
        call(:vkCmdSetScissor, [P, U, U, P], V, command, 0, 1, keep(scissor_bytes(nil)))
        call(:vkCmdBindPipeline, [P, I, Q], V, command, 0, pipeline_handle)
        call(:vkCmdDraw, [P, U, U, U, U], V, command, 3, 1, 0, 0)
        call(:vkCmdEndRenderPass, [P], V, command)
        copy_target(command)
        @pixels = submit(command, read: true)
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
