# frozen_string_literal: true

module Zaniah
  class Menu
    Item = Data.define(:action, :title, :shortcut, :role, :children, :dynamic) do
      def separator? = role == :separator
      def submenu? = role == :submenu
    end

    class Builder
      attr_reader :items

      def initialize(owner: nil)
        @items, @owner = [], owner
      end

      def item(action, title: nil, shortcut: nil, role: nil)
        raise ArgumentError, "menu action must be a Symbol or String" unless action.is_a?(Symbol) || action.is_a?(String)
        raise ArgumentError, "menu title must be a String" unless title.nil? || title.is_a?(String)
        raise ArgumentError, "menu shortcut must be a String" unless shortcut.nil? || shortcut.is_a?(String)
        raise ArgumentError, "menu role must be a Symbol" unless role.nil? || role.is_a?(Symbol)
        @items << Item.new(action: action, title: title, shortcut: shortcut, role: role, children: [].freeze, dynamic: nil)
        self
      end

      def submenu(title, items: nil, &block)
        raise ArgumentError, "provide either items: or a block" if items && block
        raise ArgumentError, "submenu title must be a String" unless title.is_a?(String)
        raise ArgumentError, "items: must be callable" if items && !items.respond_to?(:call)
        children = block ? self.class.new(owner: @owner).tap { |builder| builder.instance_eval(&block) }.items : []
        @items << Item.new(action: nil, title: title, shortcut: nil, role: :submenu,
          children: children.freeze, dynamic: items)
        self
      end

      def separator
        @items << Item.new(action: nil, title: nil, shortcut: nil, role: :separator, children: [].freeze, dynamic: nil)
        self
      end

      def app_menu = (special_menu(:app_menu); self)
      def window_menu = (special_menu(:window_menu); self)

      def standard_edit_items
        item :undo
        item :redo
        separator
        %i[cut copy paste select_all].each { |action| item(action) }
        self
      end

      private

      def method_missing(name, *args, **kwargs, &block)
        return super unless @owner&.respond_to?(name, true)
        @owner.__send__(name, *args, **kwargs, &block)
      end

      def respond_to_missing?(name, include_private = false) = @owner&.respond_to?(name, true) || super

      def special_menu(role)
        @items << Item.new(action: nil, title: nil, shortcut: nil, role: role, children: [].freeze, dynamic: nil)
      end
    end

    attr_reader :items

    def self.build(&block)
      raise ArgumentError, "menu block is required" unless block
      new(Builder.new(owner: block.binding.receiver).tap { |builder| builder.instance_eval(&block) }.items)
    end

    def initialize(items)
      raise ArgumentError, "menu items must be Menu::Item values" unless items.is_a?(Array) && items.all? { |item| item.is_a?(Item) }
      @items = items.dup.freeze
    end

    def resolve(registry: nil, keymap: nil, platform: RUBY_PLATFORM)
      @items.filter_map { |item| resolve_item(item, registry, keymap, platform) }.freeze
    end

    def children_for(item, registry: nil, keymap: nil, platform: RUBY_PLATFORM)
      children = item.dynamic ? dynamic_items(item.dynamic.call) : item.children
      self.class.new(children).resolve(registry: registry, keymap: keymap, platform: platform)
    end

    private

    def resolve_item(item, registry, keymap, platform)
      return if %i[app_menu window_menu].include?(item.role) && !platform.to_s.match?(/darwin|mac/)
      return item if item.separator?

      command = registry&.command(item.action) if item.action
      item.with(title: item.title || command&.title&.to_s || item.action&.to_s,
        shortcut: item.shortcut || (item.action && keymap&.shortcut_for(item.action)))
    end

    def dynamic_items(value)
      value = value.items if value.is_a?(Menu)
      raise ArgumentError, "dynamic menu items must be Menu::Item values" unless value.is_a?(Array) && value.all? { |item| item.is_a?(Item) }
      value
    end
  end
end
