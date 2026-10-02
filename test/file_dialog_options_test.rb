# frozen_string_literal: true

require "test_helper"
require "zaniah/platform/linux"
require "zaniah/platform/windows"

class FileDialogOptionsTest < Minitest::Test
  def test_linux_dialog_passes_filename_and_filters_as_arguments
    window = Zaniah::Platform::Linux::Window.allocate
    captured = nil
    invoke = ->(*command) { captured = command; ["/tmp/capture.pcapng\n", Struct.new(:success?).new(true)] }
    Open3.stub(:capture2, invoke) do
      assert_equal ["/tmp/capture.pcapng"], window.prompt_for_paths(save: true, default_name: "capture.pcapng", directory: "/tmp", filters: [{label: "Capture files", patterns: ["*.pcapng", "*.pcap"]}])
    end
    assert_includes captured, "--filename=/tmp/capture.pcapng"
    assert_includes captured, "--file-filter=Capture files | *.pcapng *.pcap"
    assert_includes captured, "--confirm-overwrite"
    assert_raises(ArgumentError) { window.prompt_for_paths(default_name: "../capture") }
    assert_raises(ArgumentError) { window.prompt_for_paths(filters: [{label: "bad", patterns: ["*.pcap;*.txt"]}]) }
  end

  def test_windows_dialog_sets_unicode_buffers_and_preserves_working_directory
    window = Zaniah::Platform::Windows::Window.allocate
    window.instance_variable_set(:@handle, 0)
    checked = false
    function = ->(dialog) do
      checked = true
      assert_equal "capture.pcapng", dialog.file[0, 28].force_encoding("UTF-16LE").encode("UTF-8").delete("\0")
      assert_equal "/tmp\0".encode("UTF-16LE").b, dialog.initial_dir[0, 10]
      filter = "Capture files\0*.pcapng;*.pcap\0\0".encode("UTF-16LE").b
      assert_equal filter, dialog["filter"][0, filter.bytesize]
      assert_operator dialog.flags & 0x8, :>, 0
      0
    end
    library = Object.new
    library.define_singleton_method(:fn) { |*_args| function }
    Zaniah::FFI::Library.stub(:new, library) do
      assert_empty window.prompt_for_paths(save: true, default_name: "capture.pcapng", directory: "/tmp", filters: [{label: "Capture files", patterns: ["*.pcapng", "*.pcap"]}])
    end
    assert checked
  end

  def test_mac_dialog_sets_name_directory_and_extensions_without_opening_panel
    skip "macOS runtime only" unless RUBY_PLATFORM.include?("darwin")
    require "zaniah/platform/mac"
    window = Zaniah::Platform::Mac::Window.allocate
    calls = []
    send_native = ->(object, selector, *arguments, **_options) do
      calls << [selector, arguments]
      selector == "runModal" ? 0 : 100
    end
    window.define_singleton_method(:cocoa_array) { |values| values }
    objc = Zaniah::Platform::Mac::O
    objc.stub(:klass, 10) do
      objc.stub(:string, ->(text) { text }) do
        objc.stub(:send, send_native) do
          assert_empty window.prompt_for_paths(save: true, default_name: "capture.pcapng", directory: "/tmp", filters: [{label: "Capture files", patterns: ["*.pcapng", "*.pcap"]}])
        end
      end
    end
    assert_includes calls, ["setNameFieldStringValue:", ["capture.pcapng"]]
    assert_includes calls, ["fileURLWithPath:", ["/tmp"]]
    assert_includes calls, ["setAllowedFileTypes:", [["pcapng", "pcap"]]]
  end
end
