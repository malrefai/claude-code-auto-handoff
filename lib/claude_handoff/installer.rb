# frozen_string_literal: true

require 'json'
require 'shellwords'
require 'fileutils'
require 'rbconfig'

module ClaudeHandoff
  # Wires the statusline sidecar into ~/.claude/settings.json.
  #
  # Claude Code allows exactly one statusLine command, so installing has to
  # displace whatever the user already had. The displaced command is saved
  # outside settings.json — adding an unknown key to a file with a schema is a
  # good way to have it stripped — and the sidecar replays stdin to it.
  class Installer
    def initialize(state_root: Config.state_dir_from_env, settings_path: nil, out: $stdout)
      @state_root = state_root
      @settings_path = settings_path || self.class.default_settings_path
      @out = out
    end

    def self.default_settings_path
      override = ENV.fetch('CLAUDE_HANDOFF_SETTINGS_PATH', nil)
      return File.expand_path(override) if override && !override.empty?

      File.expand_path('~/.claude/settings.json')
    end

    # Pins the interpreter rather than relying on the shebang. Claude Code runs
    # this command with whatever PATH it happens to have, and macOS still ships
    # a Ruby 2.6 at /usr/bin/ruby that would fail to run this code.
    def statusline_command
      "#{Shellwords.escape(RbConfig.ruby)} " \
        "#{Shellwords.escape(ClaudeHandoff.program_path)} statusline"
    end

    # Distinctive enough to recognise our own command without matching a user
    # command that merely mentions "cld".
    MARKER = 'cld statusline'

    def install
      settings = read_settings
      existing = settings.dig('statusLine', 'command')

      if existing.to_s.include?(MARKER)
        say 'statusline sidecar already installed'
      else
        if existing && !existing.empty?
          FileUtils.mkdir_p(@state_root)
          File.write(inner_path, existing)
          say 'chained the sidecar in front of your existing statusline'
          say "(previous command saved to #{inner_path})"
        else
          say 'installed the statusline sidecar'
        end
        settings['statusLine'] = { 'type' => 'command', 'command' => statusline_command }
        write_settings(settings)
      end

      say ''
      say 'Done. Run `cld` instead of `claude`, and check state with `cld status`.'
      self
    end

    # Returns self, not a success flag: whether the sidecar is wired up is a
    # question for `installed?`, and callers should not branch on an action.
    def uninstall
      settings = read_settings
      existing = settings.dig('statusLine', 'command')

      unless existing.to_s.include?(MARKER)
        say 'statusline sidecar is not installed'
        return self
      end

      inner = File.file?(inner_path) ? File.read(inner_path).strip : nil
      if inner && !inner.empty?
        settings['statusLine'] = { 'type' => 'command', 'command' => inner }
        say 'restored your previous statusline command'
      else
        settings.delete('statusLine')
        say 'removed the statusline sidecar'
      end

      write_settings(settings)
      FileUtils.rm_f(inner_path)
      self
    end

    def installed?
      read_settings.dig('statusLine', 'command').to_s.include?(MARKER)
    end

    private

    def inner_path = File.join(@state_root, 'inner-statusline')

    def say(message) = @out.puts(message)

    def read_settings
      return {} unless File.file?(@settings_path)

      parsed = JSON.parse(File.read(@settings_path))
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      raise Error, "#{@settings_path} is not valid JSON; fix it and try again"
    end

    # Rewrites the whole file, so every unrelated key has to survive the
    # round-trip untouched.
    def write_settings(settings)
      FileUtils.mkdir_p(File.dirname(@settings_path))
      tmp = "#{@settings_path}.claude-handoff.tmp"
      File.write(tmp, "#{JSON.pretty_generate(settings)}\n")
      File.rename(tmp, @settings_path)
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp.to_s)
    end
  end
end
