# frozen_string_literal: true

require "json"

module Zaniah
  # Only primitive JSON data crosses this local, trusted-code boundary. No
  # Marshal hooks, constant reconstruction, source text or eval is involved.
  module ProcessWire
    MAX_DEPTH = 64
    MAX_NODES = 1_000_000

    def self.validate_payload(value, depth = 0, budget = [MAX_NODES, nil, nil], freeze: false)
      raise ArgumentError, "IPC data is too deeply nested" if depth > MAX_DEPTH
      raise ArgumentError, "IPC data has too many values" if (budget[0] -= 1).negative?
      case value.class.name
      when "NilClass", "TrueClass" then charge_budget(budget, 4)
      when "FalseClass" then charge_budget(budget, 5)
      when "Integer"
        raise ArgumentError, "IPC integer exceeds byte budget" if budget[1] && value.bit_length > budget[1] * 4
        charge_budget(budget, value.to_s.bytesize)
      when "Float"
        raise ArgumentError, "IPC numbers must be finite" unless value.finite?
        charge_budget(budget, value.to_s.bytesize)
      when "String"
        raise ArgumentError, "IPC strings must be valid UTF-8" unless value.valid_encoding? &&
          (value.encoding == Encoding::UTF_8 || value.ascii_only?)
        if budget[1]
          charge_budget(budget, value.bytesize + 2)
          # JSON escapes quotes/backslashes and control characters. Count in
          # native String scans before generating any potentially large JSON.
          charge_budget(budget, value.count('"') + value.count("\\") +
            value.count("\x00-\x1f") * 5 - value.count("\b\t\n\f\r") * 4)
        end
      when "Array"
        charge_budget(budget, 2 + [value.length - 1, 0].max)
        value.each { |item| validate_payload(item, depth + 1, budget, freeze: freeze) }
      when "Hash"
        charge_budget(budget, 2 + value.length + [value.length - 1, 0].max)
        value.each do |key, item|
          raise ArgumentError, "IPC object keys must be strings" unless key.instance_of?(String)
          validate_payload(key, depth + 1, budget, freeze: freeze)
          validate_payload(item, depth + 1, budget, freeze: freeze)
        end
      else
        raise ArgumentError, "IPC values must be plain JSON data"
      end
      value.freeze if freeze
      value
    end

    def self.charge_budget(budget, bytes)
      return unless budget[1]
      raise ArgumentError, "IPC frame exceeds #{budget[2]} bytes" if (budget[1] -= bytes).negative?
    end

    def self.encode_frame(value, max_bytes)
      validate_payload(value, 0, [MAX_NODES, max_bytes, max_bytes])
      body = JSON.generate(value, max_nesting: MAX_DEPTH)
      raise ArgumentError, "IPC frame exceeds #{max_bytes} bytes" if body.bytesize > max_bytes
      [body.bytesize].pack("N") + body.b
    end

    def self.read_payload(io, max_bytes)
      header = io.read(4)
      return if header.nil?
      raise IOError, "truncated IPC header" unless header.bytesize == 4
      length = header.unpack1("N")
      raise IOError, "invalid IPC frame length" unless length.between?(1, max_bytes)
      body = io.read(length)
      raise IOError, "truncated IPC payload" unless body && body.bytesize == length
      body.force_encoding(Encoding::UTF_8)
      raise IOError, "invalid IPC UTF-8" unless body.valid_encoding?
      body
    end

    def self.decode_payload(body)
      validate_payload(JSON.parse(body, max_nesting: MAX_DEPTH, create_additions: false), freeze: true)
    end

    def self.error_message(error)
      "#{error.class}: #{error.message}".encode(Encoding::UTF_8, invalid: :replace, undef: :replace).byteslice(0, 2048).scrub("")
    end

    private_class_method :validate_payload, :charge_budget

    def self.serve(input, output, max_bytes, handler)
      input.binmode
      output.binmode
      output.sync = true
      while (body = read_payload(input, max_bytes))
        response = begin
          encode_frame([true, handler.call(decode_payload(body))], max_bytes)
        rescue StandardError => error
          encode_frame([false, error_message(error)], max_bytes)
        end
        output.write(response)
      end
    end

    def self.run
      # Keep protocol output private; even a required file's `puts` is harmless.
      output = STDOUT.dup
      STDOUT.reopen(STDERR)
      $stdout = STDERR
      name, maximum, *requires = ARGV
      raise ArgumentError, "invalid worker handler" unless name&.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
      max_bytes = Integer(maximum)
      requires.each { |path| require path }
      handler = name.split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      raise ArgumentError, "worker handler must respond to .call" unless handler.is_a?(Module) && handler.respond_to?(:call)
      serve(STDIN, output, max_bytes, handler)
    rescue StandardError => error
      output.write(encode_frame([false, error_message(error)], max_bytes)) if output && max_bytes
    ensure
      output&.close
    end
  end
end

if $PROGRAM_NAME == __FILE__
  # Ruby does not put its entry script in $LOADED_FEATURES. A handler may load
  # zaniah, which requires this file again through ProcessPool; register it
  # before loading handlers so that require cannot re-enter worker startup.
  path = File.realpath(__FILE__)
  $LOADED_FEATURES << path unless $LOADED_FEATURES.include?(path)
  Zaniah::ProcessWire.run
end
