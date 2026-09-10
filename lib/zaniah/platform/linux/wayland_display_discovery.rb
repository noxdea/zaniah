# frozen_string_literal: true

require_relative "../../ffi/wayland"

module Zaniah
  module Platform
    module Linux
      module WaylandDisplayDiscovery
        module_function

        def read
          ptype, int, uint = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT
          connection, outputs, manager = FFI::Wayland.new, {}, nil
          registry = connection.request(connection.display, 1, 0, new_interface: "wl_registry", version: 1)
          connection.listen(registry, [
            [[uint, ptype, uint], ->(_registry, id, name, version) do
              name = name.to_s
              if name == "wl_output"
                output = connection.request(registry, 0, id, name, [version, 2].min, 0, new_interface: name, version: [version, 2].min)
                state = outputs[id] = {proxy: output, x: 0, y: 0, width: 0, height: 0, scale: 1, name: "Display #{id}"}
                connection.listen(output, [
                  [[int, int, int, int, int, ptype, ptype, int], ->(_output, x, y, _mw, _mh, _subpixel, make, model, transform) { state.merge!(x: x, y: y, name: "#{make.to_s} #{model.to_s}", transform: transform) }],
                  [[uint, int, int, int], ->(_output, flags, width, height, _refresh) { state.merge!(width: width, height: height) if (flags & 1) != 0 }],
                  [[], nil], [[int], ->(_output, scale) { state[:scale] = [scale, 1].max }]
                ])
              elsif name == "zxdg_output_manager_v1"
                manager = connection.request(registry, 0, id, name, [version, 3].min, 0, new_interface: name, version: [version, 3].min)
              end
            end],
            [[uint], ->(_registry, id) { outputs.delete(id) }]
          ])
          connection.roundtrip
          connection.roundtrip
          if manager
            outputs.each_value do |state|
              output = connection.request(manager, 1, 0, state[:proxy], new_interface: "zxdg_output_v1")
              connection.listen(output, [
                [[int, int], ->(_output, x, y) { state[:logical_position] = [x, y] }],
                [[int, int], ->(_output, width, height) { state[:logical_size] = [width, height] }],
                [[], nil], [[ptype], ->(_output, name) { state[:name] = name.to_s }], [[ptype], nil]
              ])
            end
            connection.roundtrip
          end
          outputs.map do |id, state|
            scale = state[:scale]
            x, y = state[:logical_position] || [state[:x] / scale.to_f, state[:y] / scale.to_f]
            width, height = state[:logical_size] || [state[:width] / scale.to_f, state[:height] / scale.to_f]
            if !state[:logical_size] && state.fetch(:transform, 0).odd?
              width, height = height, width
            end
            Display.new(id, state[:name], Bounds.new(x, y, width, height), scale, false)
          end
        ensure
          connection&.close
        end
      end
    end
  end
end
