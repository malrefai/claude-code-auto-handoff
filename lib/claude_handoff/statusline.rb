# frozen_string_literal: true

require 'json'

module ClaudeHandoff
  # Installed as the user's `statusLine.command`. Claude Code pipes a JSON blob
  # here on every render; this is the only supported source of the usage-window
  # reset times.
  #
  # Two rules govern this class:
  #   1. It must never raise. A crash here breaks the user's statusline.
  #   2. It must replay stdin to whatever statusline command it displaced, so
  #      the user's prompt looks exactly as it did before installing.
  class Statusline
    def initialize(state_root: Config.state_dir_from_env, out: $stdout)
      @state_root = state_root
      @out = out
    end

    def run(input)
      record(input)
    ensure
      chain(input)
    end

    private

    def record(input)
      payload = JSON.parse(input)
      sample = RateLimitSample.from_statusline(payload)
      return if sample.nil?
      return if sample.project_dir.nil? || sample.project_dir.empty?

      store = StateStore.new(sample.project_dir, root: @state_root)
      store.ensure_project_dir
      store.write_limits(sample.to_h)
    rescue StandardError
      # Malformed payload, unwritable state dir, anything: stay silent and let
      # the user's statusline render.
      nil
    end

    def chain(input)
      inner = ENV.fetch('CLAUDE_HANDOFF_INNER_STATUSLINE', nil)
      inner = StateStore.new(Dir.pwd, root: @state_root).inner_statusline if inner.nil? || inner.empty?
      return if inner.nil? || inner.empty?

      # The displaced command was a shell string in settings.json, so it has to
      # run through a shell to keep working. It is the user's own configured
      # command, not attacker-controlled input.
      IO.popen(['/bin/sh', '-c', inner], 'r+') do |io|
        io.write(input)
        io.close_write
        @out.write(io.read)
      end
    rescue StandardError
      nil
    end
  end
end
