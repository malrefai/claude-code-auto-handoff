# frozen_string_literal: true

require 'time'

module ClaudeHandoff
  # Argument handling and small formatting helpers for the CLI.
  #
  # Because `cld` stands in for `claude`, it cannot use a normal option parser:
  # an unrecognised flag is not an error, it belongs to Claude Code. So our own
  # options are namespaced with `--handoff-` and everything else is collected
  # untouched.
  module Arguments
    # Our own options. Anything not listed here is passed through.
    FLAGS = {
      '--handoff-yes' => %i[assume_yes flag],
      '--handoff-threshold' => %i[threshold float],
      '--handoff-permission-mode' => %i[permission_mode string],
      '--handoff-strategy' => %i[resume_strategy string],
      '--handoff-scheduler' => %i[scheduler string],
      '--handoff-word-budget' => %i[handoff_word_budget int]
    }.freeze

    module_function

    # Splits argv into our namespaced options and everything destined for
    # Claude Code. A bare `--` ends our parsing: the rest is passed through
    # verbatim, so a literal `--handoff-*` argument can still reach Claude Code.
    def extract_flags(argv)
      opts = {}
      passthrough = []
      index = 0

      while index < argv.length
        arg = argv[index]

        if arg == '--'
          passthrough.concat(argv[(index + 1)..])
          break
        end

        index = consume(argv, index, opts, passthrough)
      end

      [opts, passthrough]
    end

    # Handles one argument, returning the next index to read.
    def consume(argv, index, opts, passthrough)
      arg = argv[index]
      name, inline = arg.split('=', 2)
      spec = FLAGS[name]

      if spec.nil?
        passthrough << arg
        return index + 1
      end

      key, type = spec
      if type == :flag
        opts[key] = true
        return index + 1
      end

      value = inline || argv[index += 1]
      raise Error, "#{name} requires a value" if value.nil?

      opts[key] = cast(name, value, type)
      index + 1
    end

    def cast(name, value, type)
      case type
      when :int then Integer(value, exception: false) || invalid(name, value)
      when :float then Float(value, exception: false) || invalid(name, value)
      else value
      end
    end

    def invalid(name, value)
      raise Error, "#{name} expects a number, got #{value.inspect}"
    end

    # Resolves an executable the way a shell would.
    def which(name)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
        candidate = File.join(dir, name)
        return candidate if File.executable?(candidate) && !File.directory?(candidate)
      end
      nil
    end

    def fmt_time(epoch)
      return 'unknown' if epoch.nil?

      Time.at(epoch.to_i).strftime('%Y-%m-%d %H:%M:%S %Z')
    end
  end
end
