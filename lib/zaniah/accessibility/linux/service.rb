# frozen_string_literal: true

require "fiddle"
require "open3"
require_relative "../../ffi/library"

module Zaniah
  module Accessibility
    module Linux
      class Service
        attr_reader :unique_name
        P = Fiddle::TYPE_VOIDP
        I = Fiddle::TYPE_INT
        U = Fiddle::TYPE_UINT
        ROOT_PATH = "/org/a11y/atspi/accessible/root"
        NULL_PATH = "/org/a11y/atspi/null"
        ACCESSIBLE = "org.a11y.atspi.Accessible"
        COMPONENT = "org.a11y.atspi.Component"
        ACTION = "org.a11y.atspi.Action"
        APPLICATION = "org.a11y.atspi.Application"

        ROLES = {
          application: 75, button: 43, checkbox: 7, radio: 44, switch: 62, textbox: 79,
          searchbox: 79, combobox: 11, listbox: 98, dialog: 16, table: 55, row: 90,
          cell: 56, columnheader: 57, tree: 65, treeitem: 91, list: 31, listitem: 32,
          slider: 51, progressbar: 42, meter: 103, link: 88, image: 27, heading: 83,
          text: 61, separator: 50, toolbar: 63, menubar: 34, menu: 33, menuitem: 35,
          tab: 37, tabpanel: 38, tooltip: 64, status: 54, navigation: 110,
          radiogroup: 99, form: 87, group: 99
        }.freeze

        XML = <<~XML.freeze
          <node>
            <interface name="#{ACCESSIBLE}">
              <property name="Name" type="s" access="read"/><property name="Description" type="s" access="read"/>
              <property name="Parent" type="(so)" access="read"/><property name="ChildCount" type="i" access="read"/>
              <property name="Locale" type="s" access="read"/><property name="AccessibleId" type="s" access="read"/>
              <property name="HelpText" type="s" access="read"/>
              <method name="GetChildAtIndex"><arg type="i" direction="in"/><arg type="(so)" direction="out"/></method>
              <method name="GetChildren"><arg type="a(so)" direction="out"/></method>
              <method name="GetIndexInParent"><arg type="i" direction="out"/></method>
              <method name="GetRelationSet"><arg type="a(ua(so))" direction="out"/></method>
              <method name="GetRole"><arg type="u" direction="out"/></method>
              <method name="GetRoleName"><arg type="s" direction="out"/></method>
              <method name="GetLocalizedRoleName"><arg type="s" direction="out"/></method>
              <method name="GetState"><arg type="au" direction="out"/></method>
              <method name="GetAttributes"><arg type="a{ss}" direction="out"/></method>
              <method name="GetApplication"><arg type="(so)" direction="out"/></method>
              <method name="GetInterfaces"><arg type="as" direction="out"/></method>
            </interface>
            <interface name="#{COMPONENT}">
              <method name="Contains"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="in"/><arg type="b" direction="out"/></method>
              <method name="GetAccessibleAtPoint"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="in"/><arg type="(so)" direction="out"/></method>
              <method name="GetExtents"><arg type="u" direction="in"/><arg type="(iiii)" direction="out"/></method>
              <method name="GetPosition"><arg type="u" direction="in"/><arg type="i" direction="out"/><arg type="i" direction="out"/></method>
              <method name="GetSize"><arg type="i" direction="out"/><arg type="i" direction="out"/></method>
              <method name="GetLayer"><arg type="u" direction="out"/></method><method name="GetMDIZOrder"><arg type="n" direction="out"/></method>
              <method name="GrabFocus"><arg type="b" direction="out"/></method><method name="GetAlpha"><arg type="d" direction="out"/></method>
            </interface>
            <interface name="#{ACTION}">
              <property name="NActions" type="i" access="read"/>
              <method name="GetDescription"><arg type="i" direction="in"/><arg type="s" direction="out"/></method>
              <method name="GetName"><arg type="i" direction="in"/><arg type="s" direction="out"/></method>
              <method name="GetLocalizedName"><arg type="i" direction="in"/><arg type="s" direction="out"/></method>
              <method name="GetKeyBinding"><arg type="i" direction="in"/><arg type="s" direction="out"/></method>
              <method name="DoAction"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
            </interface>
            <interface name="#{APPLICATION}">
              <property name="ToolkitName" type="s" access="read"/><property name="Version" type="s" access="read"/>
              <property name="ToolkitVersion" type="s" access="read"/><property name="AtspiVersion" type="s" access="read"/>
              <property name="InterfaceVersion" type="u" access="read"/><property name="Id" type="i" access="readwrite"/>
              <method name="GetLocale"><arg type="u" direction="in"/><arg type="s" direction="out"/></method>
              <method name="GetApplicationBusAddress"><arg type="s" direction="out"/></method>
            </interface>
          </node>
        XML

        INSTANCES = {}

        def initialize(window)
          @window, @registrations, @application_id = window, {}, -1
          connect
          install_callbacks
          parse_interfaces
        end

        def update(root)
          application = Accessibility.node(role: :application, label: window_title,
            bounds: root.bounds, children: [root])
          @tree = NativeTree.new(application)
          @entries = @tree.to_h { |entry| [path(entry), entry] }
          (@registrations.keys - @entries.keys).each { |object_path| unregister(object_path) }
          (@entries.keys - @registrations.keys).each { |object_path| register(object_path) }
          embed unless @embedded
          emit_change
          true
        end

        def poll = glib.fn(:g_main_context_iteration, [P, I], I).call(0, 0)

        def close
          @registrations.keys.each { |object_path| unregister(object_path) }
          object.fn(:g_object_unref, [P], Fiddle::TYPE_VOID).call(@connection) if @connection&.to_i&.positive?
          gio.fn(:g_dbus_node_info_unref, [P], Fiddle::TYPE_VOID).call(@node_info) if @node_info&.to_i&.positive?
          INSTANCES.delete(object_id)
          true
        end

        private

        def connect
          address = ENV["AT_SPI_BUS_ADDRESS"] || accessibility_bus_address
          raise Error, "AT-SPI accessibility bus is unavailable" if address.to_s.empty?
          error = [0].pack("J")
          @connection = gio.fn(:g_dbus_connection_new_for_address_sync, [P, I, P, P, P], P)
            .call(address, 9, 0, 0, error)
          raise Error, "cannot connect to AT-SPI accessibility bus" if @connection.to_i.zero?
          gio.fn(:g_dbus_connection_set_exit_on_close, [P, I], Fiddle::TYPE_VOID).call(@connection, 0)
          @unique_name = pointer_text(gio.fn(:g_dbus_connection_get_unique_name, [P], P).call(@connection))
        end

        def accessibility_bus_address
          output, _error, status = Open3.capture3("gdbus", "call", "--session", "--dest", "org.a11y.Bus",
            "--object-path", "/org/a11y/bus", "--method", "org.a11y.Bus.GetAddress")
          status.success? ? output[/\('([^']+)'/, 1] : nil
        end

        def install_callbacks
          INSTANCES[object_id] = self
          @method_callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [P] * 8) do |_connection, _sender, object_path, interface, method, parameters, invocation, data|
            INSTANCES[data.to_i]&.__send__(:method_call, pointer_text(object_path), pointer_text(interface), pointer_text(method), parameters, invocation)
          rescue StandardError => error
            INSTANCES[data.to_i]&.__send__(:return_error, invocation, error)
          end
          @get_callback = Fiddle::Closure::BlockCaller.new(P, [P] * 7) do |_connection, _sender, object_path, interface, property, _error, data|
            INSTANCES[data.to_i]&.__send__(:property, pointer_text(object_path), pointer_text(interface), pointer_text(property)) || 0
          rescue StandardError
            0
          end
          @set_callback = Fiddle::Closure::BlockCaller.new(I, [P] * 8) do |_connection, _sender, object_path, interface, property, value, _error, data|
            INSTANCES[data.to_i]&.__send__(:set_property, pointer_text(object_path), pointer_text(interface), pointer_text(property), value) ? 1 : 0
          rescue StandardError
            0
          end
          @vtable = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP * 11)
          @vtable[0, Fiddle::SIZEOF_VOIDP * 11] = [@method_callback.to_i, @get_callback.to_i, @set_callback.to_i, *([0] * 8)].pack("J*")
        end

        def parse_interfaces
          error = [0].pack("J")
          @node_info = gio.fn(:g_dbus_node_info_new_for_xml, [P, P], P).call(XML, error)
          raise Error, "invalid AT-SPI introspection data" if @node_info.to_i.zero?
          @interfaces = [ACCESSIBLE, COMPONENT, ACTION, APPLICATION].to_h do |name|
            [name, gio.fn(:g_dbus_node_info_lookup_interface, [P, P], P).call(@node_info, name)]
          end
        end

        def register(object_path)
          names = [ACCESSIBLE, COMPONENT, ACTION]
          names << APPLICATION if object_path == ROOT_PATH
          ids = names.map do |name|
            gio.fn(:g_dbus_connection_register_object, [P, P, P, P, P, P, P], U)
              .call(@connection, object_path, @interfaces.fetch(name), @vtable, object_id, 0, 0)
          end
          raise Error, "cannot register AT-SPI object #{object_path}" if ids.any?(&:zero?)
          @registrations[object_path] = ids
        end

        def unregister(object_path)
          @registrations.delete(object_path)&.each do |id|
            gio.fn(:g_dbus_connection_unregister_object, [P, U], I).call(@connection, id)
          end
        end

        def embed
          gio.fn(:g_dbus_connection_call, [P, P, P, P, P, P, P, I, I, P, P, P], Fiddle::TYPE_VOID)
            .call(@connection, "org.a11y.atspi.Registry", ROOT_PATH, "org.a11y.atspi.Socket", "Embed",
              tuple(reference(@tree.root)), 0, 0, 3000, 0, 0, 0)
          @embedded = true
        end

        def emit_change
          parameters = tuple(string(""), int32(0), int32(0), variant(string("")), array("{sv}", []))
          gio.fn(:g_dbus_connection_emit_signal, [P, P, P, P, P, P, P], I)
            .call(@connection, 0, ROOT_PATH, "org.a11y.atspi.Event.Object", "VisibleDataChanged", parameters, 0)
        end

        def method_call(object_path, interface, method, parameters, invocation)
          entry = @entries[object_path]
          raise Error, "unknown accessible object" unless entry
          values = case interface
          when ACCESSIBLE then accessible_method(entry, method, parameters)
          when COMPONENT then component_method(entry, method, parameters)
          when ACTION then action_method(entry, method, parameters)
          when APPLICATION then application_method(method)
          else raise Error, "unknown accessibility interface"
          end
          gio.fn(:g_dbus_method_invocation_return_value, [P, P], Fiddle::TYPE_VOID).call(invocation, tuple(*Array(values)))
        end

        def accessible_method(entry, method, parameters)
          case method
          when "GetChildAtIndex" then reference(entry.children[parameter(parameters, 0, :int32)])
          when "GetChildren" then array("(so)", entry.children.map { |child| reference(child) })
          when "GetIndexInParent" then int32(entry.parent ? entry.parent.children.index(entry) : -1)
          when "GetRelationSet" then array("(ua(so))", [])
          when "GetRole" then uint32(ROLES.fetch(entry.node.role, 67))
          when "GetRoleName", "GetLocalizedRoleName" then string(entry.node.role.to_s.tr("_", " "))
          when "GetState" then array("u", states(entry).map { |state| uint32(state) })
          when "GetAttributes" then array("{ss}", entry.node.states.map { |key, value| dict(string(key), string(value)) })
          when "GetApplication" then reference(@tree.root)
          when "GetInterfaces"
            names = [ACCESSIBLE, COMPONENT]
            names << ACTION unless entry.node.actions.empty?
            names << APPLICATION if entry.equal?(@tree.root)
            array("s", names.map { |name| string(name) })
          else raise Error, "unsupported Accessible method #{method}"
          end
        end

        def component_method(entry, method, parameters)
          bounds = @tree.bounds(entry)
          case method
          when "Contains"
            point = Point.new(parameter(parameters, 0, :int32), parameter(parameters, 1, :int32))
            boolean(bounds.contains?(point))
          when "GetAccessibleAtPoint"
            point = Point.new(parameter(parameters, 0, :int32), parameter(parameters, 1, :int32))
            reference(@tree.hit(point))
          when "GetExtents" then tuple(*[bounds.x, bounds.y, bounds.width, bounds.height].map { |value| int32(value.round) })
          when "GetPosition" then [int32(bounds.x.round), int32(bounds.y.round)]
          when "GetSize" then [int32(bounds.width.round), int32(bounds.height.round)]
          when "GetLayer" then uint32(3)
          when "GetMDIZOrder" then int16(-1)
          when "GrabFocus"
            point = Point.new(bounds.x + bounds.width / 2.0, bounds.y + bounds.height / 2.0)
            boolean(Accessibility.focus_at(@window, point))
          when "GetAlpha" then double(1.0)
          else raise Error, "unsupported Component method #{method}"
          end
        end

        def action_method(entry, method, parameters)
          index = parameter(parameters, 0, :int32)
          action = entry.node.actions[index]
          case method
          when "GetDescription" then string(action ? "Perform #{action.to_s.tr("_", " ")}" : "")
          when "GetName", "GetLocalizedName" then string(action&.to_s || "")
          when "GetKeyBinding" then string("")
          when "DoAction" then boolean(action ? Accessibility.perform(@window, entry.node, action, bounds: @tree.bounds(entry)) : false)
          else raise Error, "unsupported Action method #{method}"
          end
        end

        def application_method(method)
          case method
          when "GetLocale" then string(ENV["LANG"] || "C")
          when "GetApplicationBusAddress" then string(ENV["AT_SPI_BUS_ADDRESS"] || "")
          else raise Error, "unsupported Application method #{method}"
          end
        end

        def property(object_path, interface, name)
          entry = @entries[object_path]
          return 0 unless entry
          case [interface, name]
          when [ACCESSIBLE, "Name"] then string(entry.node.label || entry.node.value&.to_s || entry.node.role.to_s)
          when [ACCESSIBLE, "Description"], [ACCESSIBLE, "HelpText"] then string("")
          when [ACCESSIBLE, "Parent"] then reference(entry.parent)
          when [ACCESSIBLE, "ChildCount"] then int32(entry.children.length)
          when [ACCESSIBLE, "Locale"] then string(ENV["LANG"] || "C")
          when [ACCESSIBLE, "AccessibleId"] then string(entry.runtime_id.to_s)
          when [ACTION, "NActions"] then int32(entry.node.actions.length)
          when [APPLICATION, "ToolkitName"] then string("Zaniah")
          when [APPLICATION, "Version"], [APPLICATION, "ToolkitVersion"] then string(Zaniah::VERSION)
          when [APPLICATION, "AtspiVersion"] then string("2.1")
          when [APPLICATION, "InterfaceVersion"] then uint32(1)
          when [APPLICATION, "Id"] then int32(@application_id)
          else 0
          end
        end

        def set_property(object_path, interface, name, value)
          return false unless object_path == ROOT_PATH && interface == APPLICATION && name == "Id"
          @application_id = glib.fn(:g_variant_get_int32, [P], I).call(value)
          true
        end

        def states(entry)
          node = entry.node
          values = [25, 30]
          values.concat([8, 24]) unless node.states[:disabled]
          values << 3 if node.states[:busy]
          values << 4 if node.states[:checked]
          values << 41 if node.states.key?(:checked) || node.states.key?(:mixed)
          values.concat([9, node.states[:expanded] ? 10 : 5]) unless node.states[:expanded].nil?
          focusable = !node.states[:disabled] && (!node.actions.empty? || %i[textbox searchbox slider combobox].include?(node.role))
          values << 11 if focusable
          values << 12 if @tree.focused(@window).equal?(entry)
          values << 7 if %i[textbox searchbox].include?(node.role) && !node.states[:readonly] && !node.states[:disabled]
          values << 16 if node.states[:modal]
          values << 17 if node.states[:multiline]
          values << 18 if node.states[:multiselectable]
          values << 20 if node.states[:pressed]
          values << 21 if node.states[:resizable]
          values << 22 if node.states.key?(:selected)
          values << 23 if node.states[:selected]
          values << 43 if node.states[:readonly]
          values.uniq
        end

        def reference(entry)
          entry ? tuple(string(@unique_name), object_path(path(entry))) : tuple(string(""), object_path(NULL_PATH))
        end

        def path(entry) = entry.path.empty? ? ROOT_PATH : "/org/a11y/atspi/accessible/#{entry.runtime_id}"
        def window_title = @window.respond_to?(:title) ? @window.title.to_s : "Zaniah application"

        def parameter(parameters, index, type)
          child = glib.fn(:g_variant_get_child_value, [P, Fiddle::TYPE_SIZE_T], P).call(parameters, index)
          result = glib.fn(:"g_variant_get_#{type}", [P], type == :uint32 ? U : I).call(child)
          glib.fn(:g_variant_unref, [P], Fiddle::TYPE_VOID).call(child)
          result
        end

        def tuple(*values) = container(:g_variant_new_tuple, values)
        def array(type, values)
          variant_type = glib.fn(:g_variant_type_new, [P], P).call(type)
          result = container(:g_variant_new_array, values, variant_type)
          glib.fn(:g_variant_type_free, [P], Fiddle::TYPE_VOID).call(variant_type)
          result
        end
        def container(function, values, prefix = nil)
          pointers = values.empty? ? 0 : Fiddle::Pointer[values.map(&:to_i).pack("J*")]
          arguments = prefix ? [prefix, pointers, values.length] : [pointers, values.length]
          types = prefix ? [P, P, Fiddle::TYPE_SIZE_T] : [P, Fiddle::TYPE_SIZE_T]
          glib.fn(function, types, P).call(*arguments)
        end
        def dict(key, value) = glib.fn(:g_variant_new_dict_entry, [P, P], P).call(key, value)
        def variant(value) = glib.fn(:g_variant_new_variant, [P], P).call(value)
        def string(value) = glib.fn(:g_variant_new_string, [P], P).call(value.to_s)
        def object_path(value) = glib.fn(:g_variant_new_object_path, [P], P).call(value)
        def int16(value) = glib.fn(:g_variant_new_int16, [Fiddle::TYPE_SHORT], P).call(value)
        def int32(value) = glib.fn(:g_variant_new_int32, [I], P).call(value)
        def uint32(value) = glib.fn(:g_variant_new_uint32, [U], P).call(value)
        def boolean(value) = glib.fn(:g_variant_new_boolean, [I], P).call(value ? 1 : 0)
        def double(value) = glib.fn(:g_variant_new_double, [Fiddle::TYPE_DOUBLE], P).call(value)

        def return_error(invocation, error)
          gio.fn(:g_dbus_method_invocation_return_dbus_error, [P, P, P], Fiddle::TYPE_VOID)
            .call(invocation, "org.a11y.atspi.Error.Failed", error.message)
        end

        def pointer_text(pointer) = pointer.to_i.zero? ? "" : Fiddle::Pointer.new(pointer).to_s.force_encoding(Encoding::UTF_8)
        def gio = (@gio ||= Zaniah::FFI::Library.new("libgio-2.0.so.0"))
        def glib = (@glib ||= Zaniah::FFI::Library.new("libglib-2.0.so.0"))
        def object = (@object ||= Zaniah::FFI::Library.new("libgobject-2.0.so.0"))
      end
    end
  end
end
