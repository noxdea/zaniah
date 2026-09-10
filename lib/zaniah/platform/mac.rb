# frozen_string_literal: true

require_relative "../ffi/objc"

module Zaniah
  module Platform
    module Mac
      O = FFI::ObjC
      APPKIT = FFI::Library.new("/System/Library/Frameworks/AppKit.framework/AppKit")
      QUARTZ = FFI::Library.new("/System/Library/Frameworks/QuartzCore.framework/QuartzCore")
      WINDOWS = {}
      NS_NOT_FOUND = (1 << 63) - 1
    end
  end
end

require_relative "mac/displays"
require_relative "mac/app"
require_relative "mac/window"
